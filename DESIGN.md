# routnix — design notes

This document is a running reference for the design of `routnix`
("router"+"nix"): declarative router/network-device configuration using the Nix
module system, rendered to backend-specific scripts entirely in Nix — no
external tool/build step for ordering or rendering.

**Scope note**: the name is chosen to not be RouterOS-specific, since
low-level config is inherently device-specific while a higher-level layer
could plausibly be device-agnostic later (see "High-level modules" below,
and the `virtualisation.oci-containers.backend` vs.
`virtualisation.oci-containers.containers.<name>` split it's modeled after).
**That said, this is explicitly RouterOS-only for the foreseeable future**
— the naming is just meant to avoid a rename if that ever changes, not a
commitment to build or support multiple backends now.

It's split into two parts:

- **Settled**: things that are implemented and working, described precisely.
- **Open design space**: things we've discussed and have opinions/leanings
  on, but haven't committed to. These are notes to pick the conversation
  back up from, not a spec.

## Motivation

The core shape:

- Options/config expressed via a Nix module system (`lib.evalModules`),
  including a freeform low-level DSL that maps closely to RouterOS's own
  path/field structure.
- The end product is a `.rsc` script, applied to the router over SSH by
  copying it over and running `/import`.

Design priorities:

- Nix at core: the entire pipeline — module evaluation, dependency
  ordering, and rendering — is plain Nix, with no external tool/build step
  in between.
- Ordering that's correct for RouterOS's positional tables (see "Ordered
  vs. keyed resources" below) — reordering declared items for an
  order-sensitive table actually reorders them on the router, rather than
  always doing a per-key upsert regardless of whether the underlying
  table is order-sensitive.
- A clearer split between *identity* (how we find/match an entry) and
  *ownership* (how we know an entry is ours to manage), so that ownership
  tracking doesn't have to be smuggled into whatever field happens to be used as
  the lookup key (see "Ownership and identity" below).

## Settled: current implementation

### Repo layout

```
modules/routeros.nix     -- the evalModules options (RouterOS-specific)
lib/toposort.nix         -- before/after -> ordered list, via lib.toposort
lib/render_rsc.nix       -- ordered routeros.config -> .rsc text
lib/render_rsc/          -- per-kind rendering helpers used by render_rsc.nix
lib/extended.nix         -- nixpkgs lib extended with routnix's own
                            functions under lib.routnix, for modules to use
lib/default.nix          -- glue: evalConfig { modules } -> evaluated config + .rsc
lib/tests/               -- pure-Nix unit tests for render_rsc.nix/toposort.nix,
                            split by topic, auto-loaded from lib/tests/default.nix
examples/basic.nix       -- example config
examples/cycle.nix       -- example that intentionally triggers a cycle error
checks/configs/          -- one focused config per feature, used by the
                            RouterOS CHR integration check below
checks/                  -- RouterOS CHR integration check and the pure-Nix unit test check
flake.nix                -- exposes packages.<system>.example (built .rsc),
                            checks.<system>.render-unit-tests, and
                            checks.<system>.routeros-<alias>, one per
                            RouterOS version in ros_versions.nix
```

### The `routeros.config` option

`modules/routeros.nix` defines:

```nix
options.routeros.config = mkOption {
  type = types.attrsOf (types.submodule {
    options = {
      kind = mkOption { type = types.enum [ "ordered" "unordered" "settings" "effect" ]; };
      before = mkOption { type = types.listOf types.str; default = [ ]; };
      after  = mkOption { type = types.listOf types.str; default = [ ]; };
      items  = mkOption {
        type = types.listOf (types.attrsOf (types.oneOf [ types.bool types.int types.str ]));
        default = [ ];
      };
      find    = mkOption { type = types.nullOr (types.functionTo (types.attrsOf itemValueType)); default = null; };
      create  = mkOption { type = types.functionTo types.str; default = item: "add " + renderArgs item; };
      settings = mkOption { type = types.attrsOf itemValueType; default = { }; };
    };
  });
  default = { };
};
```

It's nested under `routeros` (rather than living at the top level) so that
this RouterOS-specific tree is clearly scoped as such, leaving the top
level free for a possible future device-agnostic layer — see "Scope note"
above and "High-level modules" below.

`routeros.config` is keyed by **full RouterOS path, leading slash then
space-separated** (e.g. `"/ip firewall filter"`) — the form RouterOS v6
requires; v7's `/`-separated form (`/ip/firewall/filter`) is a superset
only it understands, so the space-separated form is what keeps rendered
`.rsc` scripts working on both.

This is intentionally the *lowest-level, coarsest-grained* primitive: one
entry per RouterOS path, an ordered list of items, `before`/`after` to
declare ordering relative to *other whole paths*, and `kind` to declare how
those items should be managed (see "Resource kinds" below). There is
currently no concept smaller than "a whole path" — see "Block-level
ordering" below for the finer-grained model we discussed but haven't built.

Item values are intentionally loosely typed (`bool | int | str`) — see
"Typing" below for why we're not modeling RouterOS's per-field value syntax
more strictly at this layer.

### Resource kinds

Not every RouterOS path behaves the same way (see "Ordered vs. keyed vs.
settings vs. unmanaged resources" below for the original discussion), so
every entry declares a required `kind` — no default, since picking one is
a meaningful decision rather than something safe to fall back on:

- **`"ordered"`** — position matters (firewall filter/mangle/nat, routing
  rules, queue trees). Identity is derived automatically from each
  item's own fields, exactly like `"unordered"` (see below, no `find`
  option); missing items are `add`-ed already placed as close to their
  declared position as possible, present-but-misplaced ones are
  repositioned via `move`, and entries that are no longer declared are
  always removed, e.g.:

  ```nix
  routeros.config."/ip firewall filter" = {
    kind = "ordered";
    items = [
      { chain = "input"; action = "accept"; protocol = "icmp"; comment = "allow-icmp"; }
      { chain = "input"; action = "drop"; comment = "drop-rest"; }
    ];
  };
  ```

  Reconciliation is two-phase, threading a `$managed` list of resolved
  ids across items via a shared, per-path scope. First, each item is
  resolved in turn, in a fresh script scope: if missing, it's `add`-ed
  — the first declared item `place-before=`s whatever currently sits at
  the top of the table (or is added plainly if the path is currently
  empty), every other item `place-before=`s `.nextid` of the *previous*
  declared item's just-resolved id — so a freshly-created item ends up
  correctly placed immediately, without waiting on a second pass. This
  replaced an earlier remove-all-then-readd idea, ruled out for dropping
  rule counters and connection-tracking state and momentarily leaving
  the resource unprotected. Second, a final pass walks `$managed` once
  more and `move`s anything not already immediately following its
  predecessor into place — the one case add-time placement can't cover:
  an already-present item repositioned since the last apply by
  something other than routnix. Both phases target *immediate*
  adjacency to the previous declared item, so declared items end up
  contiguous — unlike `"unordered"`, a foreign entry interleaved between
  two declared items doesn't survive reapplying; it gets pushed out of
  the gap.

  Unlike `"unordered"`, `prune` (see below) isn't optional here: since
  identity is the *whole* item, any field edit makes the previous
  version of that item stop matching, leaving it behind as an unmanaged
  duplicate once the edited item is re-added — routnix always sweeps up
  anything not in `$managed` or `ignore` to avoid accumulating these.

- **`"unordered"`** — presence, not position, matters (routes,
  address-lists, VLANs). Each item is only `add`-ed if it doesn't already
  match an existing entry:

  ```nix
  routeros.config."/ip firewall address-list" = {
    kind = "unordered";
    items = [ { address = "192.168.1.0/24"; list = "trusted-ips"; } ];
  };
  ```

  Unlike `"effect"` (see below), this kind has no `find`
  option -- and no escape hatch yet to override the following with one:
  identity is derived automatically from each item's own declared fields,
  rendered as `print count-only where k=v ...` (compared against `0`,
  rather than `find where ...` compared against `""` — a plain count
  sidesteps how `find` behaves when a query matches more than one entry).
  A field some items set and others don't renders as `!k` (RouterOS's
  "this field isn't set") for the items that don't set it, so e.g. one
  item having a `comment` and another not doesn't make them
  indistinguishable from each other. `create` (`item -> str`, raw `.rsc`
  text) defaults to a plain `add` of the item's own fields, which is
  normally all this kind needs.

  Optionally, `prune = true` removes existing entries this path doesn't
  currently declare. Each declared item's id is resolved via `find` (if
  it already exists) or `add` (if it doesn't) and recorded in a per-path
  list; `ignore` (a list of field predicates, OR'd together) is resolved
  to ids the same way, for entries managed by hand or by another tool. A
  `foreach` over the path's existing entries at apply time (Nix has no
  visibility into router state at eval time) then removes anything whose
  id is in neither list. Off by default, since removing entries is
  destructive; `kind = "ordered"` (see above) uses this same mechanism
  unconditionally instead, regardless of this option's value; `kind =
  "effect"` (below) supports it too, with a different id-resolution step.
  Setting `prune` on `"settings"` is an error. This only approximates
  ownership (see "Ownership and identity" below) — an entry that happens
  to match neither `ignore` nor any current `find` is removed even if
  routnix never created it.

- **`"settings"`** — a non-table, singleton config object (e.g.
  `/ip dhcp-server config`). `settings` (a single `attrsOf itemValueType`,
  not a list) is rendered as one `set` of all declared fields — inherently
  idempotent, no `items`/`find`/`create`/identity/ordering involved.

- **`"effect"`** — items realized via one or more RouterOS commands that
  aren't a plain `add` of the item's own fields, e.g. `/user ssh-keys`,
  where creating a key requires writing a file first and then running
  `import`:

  ```nix
  routeros.config."/user ssh-keys" = {
    kind = "effect";
    find = item: { user = item.user; };
    create = item: ''
      /file add name="${item.user}.pub" contents="${item.key}"
      import public-key-file="${item.user}.pub" user="${item.user}"
    '';
    items = [ { user = "admin"; key = "ssh-rsa AAAA..."; } ];
  };
  ```

  Same `find`-guarded per-item model as `"unordered"`, but `create`
  returns arbitrary `.rsc` text instead of relying on the default `add`.
  `create`'s text runs under the entry's own path context; a line can
  temporarily target a different absolute path (e.g. `/file add ...`)
  without losing that context for subsequent lines, since RouterOS itself
  treats a fully-qualified one-line command as a one-off, not a permanent
  context switch — routnix doesn't need its own path-tracking mechanism
  for this.

  Also supports `prune`/`ignore`, same semantics as `"unordered"` above.
  Id resolution differs from `"unordered"`, though: that kind's `create`
  defaults to a plain `add`, whose return value is captured directly as
  the id, but `"effect"`'s `create` can run arbitrary commands with no
  such guarantee (`import`, in the example above, doesn't hand back an
  id the way `add` does). Instead, once `create` has run, `find` is
  re-resolved to pick up the id -- erroring out if that still finds
  nothing (or more than one match), since a `create` that doesn't leave
  behind an entry `find` recognizes would otherwise go on rerunning (or
  get immediately swept by the same apply's prune sweep) every time.

  This is distinct from `DESIGN.md`'s original "unmanaged" idea (below) —
  hardware-bound entries identified by native name, only ever `set` — which
  remains unimplemented and un-named; `"effect"` is for resources that
  *are* created via a command, just not `add`.

For every kind above except `"settings"`, `find` (explicit or derived) is
required to actually distinguish items from each other: rendering throws
if two items in the same `items` list produce the same `find` result,
since they'd otherwise silently collapse into a single RouterOS entry
instead of two.

### Ordering (`lib/toposort.nix`)

Dependency resolution is a thin wrapper around nixpkgs' built-in
`lib.toposort` (`lib.lists.toposort :: (a -> a -> Bool) -> [a] -> { result } | { cycle, loops }`).
No external dependency (e.g. `denful/dag`) is used — `lib.toposort` already
gives us structured cycle detection, which is all we needed from either
option originally considered (`textClosureList` or a `Dag`-style library).

The comparator:

```nix
precedes = a: b:
  builtins.elem b routerosConfig.${a}.before || builtins.elem a routerosConfig.${b}.after;
```

i.e. `a` must render before `b` if `a` lists `b` in `before`, or `b` lists
`a` in `after`. On a cycle, `sortEntries` throws a message naming the cycle
and where it loops back to, rather than looping forever or producing
garbage output (verified against a deliberately cyclic example).

### Rendering (`lib/render_rsc.nix`)

For each path in dependency order, rendering branches on `kind`:

- `"ordered"`: emit `<path>` then:
  - the same ignore-resolution + `$managed` setup described below for
    `kind = "unordered"` with `prune = true` — always emitted here,
    since pruning isn't optional for this kind;
  - per item, the same per-item resolve block described below, except
    the create step: the first declared item's is
    `add place-before=([find]->0) k=v ...` (a plain `add` if the path
    is currently empty), and every later item `i`'s is
    `add place-before=([get ($managed->(i-1))]->".nextid") k=v ...` —
    placing a freshly-created item immediately next to its
    already-resolved predecessor, rather than waiting on the reorder
    pass below to fix its position;
  - a final reorder pass over `$managed`, to fix an item whose position
    drifted since the last apply from something other than routnix (the
    one case add-time placement above can't cover):
    ```
    {
      :local first ($managed->0)
      :local firstExisting ([find]->0)
      :if ($first != $firstExisting) do={ move $first destination=$firstExisting }
      :if ([:len $managed] > 1) do={
        :local prev $first
        :for i from=1 to=([:len $managed] - 1) do={
          :local cur ($managed->$i)
          :local dest ([get $prev]->".nextid")
          :if ($cur != $dest) do={ move $cur destination=$dest }
          :set prev $cur
        }
      }
    }
    ```
    `.nextid` (a RouterOS-internal per-entry property: the id of the
    entry immediately following it, or a sentinel value when it's last
    — which `move`/`add`'s `destination`/`place-before` both accept
    directly, moving/placing at the end) is what lets both this pass
    and the add-time placement above use a single lookup per item
    instead of a forward search over every later item;
  - the same prune sweep described below.
- `"unordered"` / `"effect"`: emit `<path>` then, per item, a guard block:
  ```
  :if ([<path> print count-only where k=v ...] = 0) do={
    <create item's text, indented>
  }
  ```
  built from `find item` (the query) and `create item` (the body). Uses
  `print count-only where ...` (a plain number) rather than
  `find where ...` (an id-or-empty-string) to check existence, since it
  sidesteps how `find` behaves when a query matches more than one entry.
  `kind = "unordered"`/`"effect"` with `prune = true` uses a different,
  id-tracking block instead of this guard -- see below.
- `"settings"`: emit `<path>` then a single `set k=v k=v ...` line built
  from the `settings` attrset.

For `kind = "unordered"`/`"effect"` with `prune = true`, and always for
`kind = "ordered"`, `ignore` is resolved to ids first, before any item is
processed, once per path:
```
:local ignore ({})
:set ignore ($ignore, [<path> find where k=v ...])   -- one per `ignore` predicate
```
Then each item's id is resolved and recorded in a per-path `$managed`
list instead of using the guard block above, so the sweep that follows
doesn't have to re-derive "is this entry one of ours" from `find` a
second time:
```
:local managed ({})
{
  :local item [<path> find where k=v ...]
  :if ([:len $item] > 1) do={ :error (...) }
  :if ($item = "" || [:find $ignore $item -1] >= 0) do={
    :set item [<create item's text>]
  }
  :set managed ($managed, $item)
}
```
one such block per item, in a fresh scope so `$item` doesn't collide
across items. A `find` match that's actually one of the ids already in
`$ignore` is treated the same as no match at all, so declaring an item
never silently "adopts" an entry the caller asked to leave alone -- a new
one is `add`-ed instead, even though that means two entries can end up
satisfying the same `find` query (the ignored one, and routnix's own).
`create`'s result is captured directly as the id -- a query that matched
nothing (or only an ignored entry) before creating exactly one new entry
can't turn up more than one match afterwards, so only the lookup *before*
creating needs the ambiguity check.

For `kind = "effect"`, `create`'s text can't be relied on to evaluate to
the new entry's id the way a plain `add` can, so it runs as statements
instead of being captured, and `find` is re-resolved afterward to pick
the id back up -- this time with an `:error` on *no* match too, not just
on more than one, since a `create` that doesn't leave behind an entry
`find` recognizes is a bug in that path's `find`/`create` pair, not
something to quietly leave unmanaged (which would just mean the entry
gets removed by this same apply's prune sweep, right after being
created):
```
:if ($item = "" || [:find $ignore $item -1] >= 0) do={
  <create item's text, indented>
  :set item [<path> find where k=v ...]
  :if ($item = "") do={ :error (...) }
  :if ([:len $item] > 1) do={ :error (...) }
}
```

The sweep itself is then a single array-membership check per existing
entry, rather than re-testing every entry against every current item's
`find` and every `ignore` predicate:
```
:foreach i in=[<path> find] do={
  :if ([:find ($managed,$ignore) $i -1] < 0) do={ <path> remove $i }
}
```

Entries that render to nothing (empty `items`/`settings`, and no
`prune`) are skipped entirely. Scalar value rendering rules (shared by
all of the above, and by `find`'s query and `create`'s default body):

- `bool` → `yes` / `no`
- `int`/`str` → double-quoted (`"22"`, not `22`)

`find`'s rendered query additionally supports a field being absent (used
by `kind = "unordered"`/`"ordered"`'s derived `find`, see "Resource
kinds" above, for a field some items set and others don't): it renders
as `!k` rather than `k=v`.

Field order *within* one rendered line is whatever Nix's `attrsOf`
iteration gives us (alphabetical) — this doesn't matter to RouterOS. Item
*list* order is preserved exactly as declared, which is what matters for
order-sensitive (`"ordered"`) tables.

### `evalConfig` (`lib/default.nix`)

```nix
evalConfig { modules }:
  -- evaluates `modules` (plus routnix-provided modules) via lib.evalModules,
  -- topologically sorts config.routeros.config,
  -- returns the evalModules result plus an `rsc` attribute with the
  -- rendered, ordered .rsc text.
```

This is the per-router unit of evaluation: one call = one router's config +
rendered script. See "Multi-router / flake shape" below for how this is
expected to extend to managing several routers from one flake — no rework
anticipated there, just wrapping multiple calls to this function.

`evalConfig` calls `evalModules` on the lib built by `lib/extended.nix`
(`nixpkgs lib.extend`-ed with routnix's own functions under `lib.routnix`,
the same mechanism home-manager uses for `lib.hm`), so every module's
`lib` argument already has `lib.routnix.*` available -- modules use e.g.
`lib.routnix.perPlatform` directly rather than importing a specific
`lib/*.nix` file themselves.

### Unit tests (`lib/tests/`)

`lib/tests/` exercises `lib/render_rsc.nix` and `lib/toposort.nix`
directly, via nixpkgs' `lib.runTests`, with no VM involved: exact `.rsc`
text for each `kind`'s happy path (including `deriveFind`'s `!k` rendering
for a field only some items in a list set, and `before`/`after` ordering
between whole paths), and that the documented error cases actually throw
(duplicate `find`/derived-identity within one path's `items`, `find`
missing on `kind = "effect"`, `prune = true` on `kind = "settings"` or
`"effect"`, and a dependency cycle). Tests are grouped by topic into one
file per sibling in `lib/tests/`; `lib/tests/default.nix` holds the shared
test helpers, auto-discovers and merges every sibling file's tests via
`builtins.readDir`, and runs them through `lib.runTests` -- adding a new
file to the directory is enough to have its tests picked up, nothing else
to wire up. `checks/render-unit-tests.nix` forces evaluation of
`lib/tests/` and fails the build with the failing tests' names and
expected-vs-actual values if any of them don't pass; it's exposed as
`checks.<system>.render-unit-tests` for every system in `flake.nix`.

### Integration check (`checks/`)

`ros_versions.nix` lists the RouterOS CHR versions tested against, keyed by
alias (e.g. `stable-v7`, `long-term-v6`); `images.nix` fetches each from
MikroTik as a `packages.<system>.ros-image-<alias>` derivation. `flake.nix`
turns each of those images into its own
`checks.<system>.routeros-<alias>` check, so a specific version can be built
on its own and `nix flake check` exercises all of them.

Each check boots its RouterOS CHR image under QEMU once, then runs a fixed
sequence of subtests against it (`checks/routeros_test.py`); each subtest
copies the `.rsc` rendered from one `checks/configs/*.nix` file to it over
scp, runs `/import`, and inspects the result over SSH. It uses KVM when
available and falls back to TCG otherwise; it needs network access to fetch
the image.

`checks/routeros_machine.py` wraps nixpkgs' `QemuMachine` for QEMU
lifecycle and serial-output capture only — the NixOS backdoor shell
(`.connect()`/`.execute()`) is never used, since RouterOS knows nothing
about it — and adds SSH/SCP helpers. Its `QemuStartCommand` subclass omits
virtio-serial/virtconsole so RouterOS keeps COM1 as its console. Commands
run as the default `admin` account with its empty password; no setup step
on the guest is needed.

Each `checks/configs/*.nix` file isolates one behavior (e.g.
`ordered_basic.nix`, `unordered_prune.nix`, `effect_basic.nix`), and
`checks/routeros_test.py` runs one subtest per file so a failure names the
specific feature that broke rather than "the result isn't as expected".
Most subtests clean up whatever path they touched afterward (`remove
[find ...]`); the `"ordered"`-kind group is the exception and
deliberately builds on the state the previous one left behind
(add-in-order, idempotent reapply, drift restoration via `move`, a field
edit, then `ignore`-guarded pruning) since `kind = "ordered"`'s mandatory
prune makes each apply a clean slate anyway. All subtests run regardless
of earlier failures, and
`/import`'s own textual output is checked for error-looking text (not
just its exit code, which RouterOS can report as success even when the
script errored).

## Open design space

Everything below is unresolved. It's recorded here so we don't have to
reconstruct the reasoning from scratch, not as a decision.

### Block-level ordering

`routeros.config` currently orders whole paths against each other. Real configs
(the motivating example being `/ip firewall filter`) often need several
independent, named chunks contributing to the *same* path, each ordered
relative to each other (e.g. baseline accept rules, then a rule that
depends on an address-list existing, then a final catch-all drop) — finer
than "whole path" but coarser than "every single item."

Direction discussed, not yet implemented: split into "blocks" (named,
orderable units that contribute items to a path) and "resources" (a path,
which is the atomic unit of *emission* — see next section for why). Two
independent orderings were discussed:

1. Blocks belonging to the same resource, ordered against each other via
   `beforeConfigs`/`afterConfigs` referencing other block names.
2. Resources ordered against each other, derived automatically by taking
   each block's `beforeConfigs`/`afterConfigs` references that point at a
   block belonging to a *different* resource, and promoting them to a
   resource-level edge (since all of a resource's blocks are emitted
   together atomically, "block A before block B" where B is in another
   resource necessarily means "A's whole resource before B's whole
   resource").

This was proposed as a possible replacement for a separate
`beforeResources`/`afterResources` field (referencing one block is enough
to pull in a dependency on its entire resource, once promoted) — trade-off
being that it reads as depending on an arbitrary "representative" block
rather than the resource itself. Not decided whether to keep both
mechanisms or unify on one.

Constraint identified: cross-resource ordering must be expressed only at
this promoted, whole-resource granularity — a block cannot be ordered
relative to a single item in another resource, because all items of a
resource are emitted as one atomic unit (see next section for why that
atomicity is required, not just convenient).

Also unresolved: block names were assumed to need to be **globally unique**
across the whole config (not just within their resource), since references
are bare names looked up in a flat namespace.

### Ordered vs. keyed vs. settings vs. unmanaged resources

Not every RouterOS path behaves the same way, and treating them all
uniformly via per-item find-then-upsert is insufficient. **Settled:** every entry declares which kind it is via the
required `kind` field — see "Resource kinds" above for the implemented
shape (`"ordered"`, `"unordered"`, `"settings"`, `"effect"`). What follows
is what's still open per kind.

- **`"ordered"` / positional** tables (firewall filter/mangle/nat, routing
  rules, queue trees) — position matters; RouterOS evaluates these
  top-to-bottom. **Settled and implemented**: identity is derived
  automatically from each item's own fields (same as `"unordered"`, no
  `find` option), incremental reconciliation via `add`/`add place-before=`
  and `move` (see "Resource kinds" above) — not remove-all-then-readd,
  which was ruled out for dropping rule counters and connection-tracking
  state and momentarily leaving the resource unprotected — and pruning
  is mandatory rather than optional, since identity being the whole item
  means any field edit leaves the old version behind as an unmanaged
  duplicate once the edited item is re-added. That last point also means
  update-if-differs, unlike `"unordered"`, isn't really "still open" here
  in practice: a field edit converges via remove-old/add-new rather than
  an in-place `set`, just not by that mechanism. **Still open**: the
  ownership gap described below (identity matches on value alone)
  applies here too, now for pruning as well as positioning.
- **`"unordered"` / keyed** tables (address-lists, DHCP static leases, IP
  pools) — order doesn't matter. **Settled:** find-by-identity (derived
  automatically from each item's own declared fields, no `find` option or
  escape hatch yet for this kind -- see "Resource kinds" above) then
  `add` only if missing (`create`, defaulting to a plain `add` of the
  item's own fields). **Still open:** update-if-differs is not
  implemented — an existing match is left alone even if its other fields
  have drifted from the declared item, so this isn't yet full
  find-then-upsert.
- **`"settings"`** (non-table, singleton config objects — e.g.
  `/ip dhcp-server config`) — **settled and implemented**: a single `set`
  of the `settings` attrset, no identity/ownership needed. Merging from
  multiple contributing blocks (once blocks exist, see "Block-level
  ordering" above) via plain attrset union is still open, but only because
  blocks themselves don't exist yet — the single-block case is done.
- **Unmanaged** tables (hardware-bound entries that can't be created or
  destroyed — physical interfaces, wifi radios) — identified by their real
  native name, only ever `set`, never added/removed, no ownership tag
  needed since nothing is ever claimed. **Not implemented, not yet a
  `kind` value.** Distinct from `"effect"` (which *does* create new
  router-side objects, just via a command other than a plain `add` on the
  entry's own fields) — a concrete example is needed before designing
  this one further.

Item *shape* is settled: `items` is a plain list for every kind that uses
it (`"ordered"`/`"unordered"`/`"effect"`), regardless of whether order is
semantically meaningful — list order is simply ignored by
`"unordered"`/`"effect"` rendering rather than needing a different
(attrset-keyed) shape. Identity for `"unordered"`/`"ordered"` is derived
automatically from each item's own fields; for `"effect"` it comes from
the required `find` function; neither comes from list vs. attrset
structure.

### Ownership and identity

Discussed as two separate concerns, deliberately decoupled:

- **Identity**: how we `find` an existing entry to decide add vs. update.
- **Ownership**: how we know an entry was created by us at all, so we never
  touch (update, or eventually clean up) something we didn't create —
  default unremovable firewall rules, dynamic DHCP leases, manually
  configured entries, etc.

Direction discussed: use a synthetic tag written into `comment` (default,
e.g. `routnix:<block>:<name>`, with any user-supplied comment text appended
after it) as the default identity/lookup mechanism, decoupled from
whichever real fields the item actually sets. This avoids baking the
ownership prefix into whatever field is used as the lookup key, which
breaks down when that field is a real, semantically constrained value
rather than free text with room for a prefix.

Also discussed: an escape hatch for **natural, composite-field identity**
(e.g. matching address-lists by `address` + `list` together, since an
address alone isn't unique across lists) for cases where a synthetic tag
isn't wanted or isn't available (no `comment` field on that resource).
**Settled and implemented**, differently per kind: for `kind = "effect"`,
via a required `find` (`item -> attrsOf itemValueType`, rendered as
`print count-only where k=v ...`, compared against `0`) that every such
entry states explicitly, composite or not, deliberately required rather
than defaulting to an "always add unconditionally" fallback (which would
silently duplicate entries on reapply); for `kind = "unordered"`/`"ordered"`,
identity is instead derived automatically from each item's own declared
fields (composite identity falls out of this for free, without stating
it), with no escape hatch yet to override it with a narrower or
synthetic one — see "Resource kinds" above.

Whatever identity mechanism is used, the `find` query should still require
the ownership tag to be present wherever possible — matching by value alone
risks silently claiming an entry we didn't create (a coincidentally
matching dynamic lease, a manually-added rule). This part is **not yet
implemented**: `find` as it stands today matches on value alone, with no
ownership tag folded in, so a coincidentally-matching pre-existing entry
would currently be silently treated as "already there." Consequence: no
silent "adoption" of pre-existing entries is *intended*, but nothing
enforces that yet. Whether adoption should be a deliberate opt-in feature
later is open regardless.

Not decided: exact tag format, whether the prefix is globally configurable.

`kind = "ordered"`'s derived-identity-based `place-before`/`move`
reconciliation (see "Resource kinds" above) was implemented without
waiting on this — it matches on value alone, same as
`"unordered"`/`"effect"`, so a coincidentally-matching foreign entry
could be misidentified as a declared item's position anchor and moved.
This is accepted for now as the same adoption risk already noted above,
just applied to positioning instead of update/prune — not solved by a
tag-based mechanism, if one lands later. Since pruning is mandatory for
this kind (see "Resource kinds" above), the same risk also applies to
removal here, exactly as it already does for `"unordered"`'s and
`"effect"`'s optional `prune` below.

**Partially settled and implemented** for `kind = "unordered"` (optional),
`kind = "effect"` (optional), and `kind = "ordered"` (mandatory):
stale-entry cleanup via
`prune`/`ignore` (see "Resource kinds" above) — but as an approximation
of ownership, not the tag-based mechanism discussed above. `prune`
removes anything whose id isn't recorded as managed (resolved via a
current item's identity -- derived for `"unordered"`/`"ordered"`,
explicit `find` for `"effect"`) or covered by `ignore`, with no notion
of "entries we created" distinct from "entries that happen to match" —
so it inherits the same adoption risk noted above, applied to deletion
instead of update: an entry `routnix` never created can still be pruned
if it isn't declared and isn't explicitly `ignore`d. A tag-based
ownership mechanism, if it lands later, would let pruning (and
adoption-avoidance generally) be precise instead of relying on the
caller's `ignore` list to enumerate every un-owned entry by hand.

### High-level modules over the low-level DSL

Discussed shape: low-level `routeros.config."/path".<block>` stays as a
generic escape hatch, and typed, curated modules (e.g.
`deviceConfig.firewall.sshAccess`) compile down into it by setting the
low-level attributes under the hood — same relationship as
`systemd.services.<name>` compiling down into `systemd.units.<name>.text`
in NixOS, or `virtualisation.oci-containers.containers.<name>` compiling
down to a `docker`/`podman`-specific implementation depending on
`virtualisation.oci-containers.backend`. Not started; no typed modules
exist yet, and no subsystem has been chosen to prototype first. Given the
current RouterOS-only scope (see "Scope note" at the top), there's no
`backend`-style selector to build yet either — that would only become
relevant if/when a second backend is ever pursued, which isn't planned.

### Typing

Leaning towards keeping the low-level DSL's value type loose (`bool | int | str`,
maybe plus `listOf str` with comma-joining for convenience) rather than
modeling RouterOS's per-field syntax (CIDR, MAC, port lists/ranges,
negation, etc.) generically — that seems like poor ROI at the freeform
layer. Preference is to put stricter types where we actually know the
exact semantics of a field: in the high-level typed modules, once they
exist. Not revisited since first raised; open to reconsidering once we
have a couple of high-level modules to see what they actually need.

### Apply mechanism

Not yet implemented at all. Direction: scp the rendered `.rsc` to the
router, `/import` it, wrapped in RouterOS's `/safe-mode take` / `release`
so a failure rolls back rather than leaving a half-applied config. Open questions not yet discussed in depth: dry-run/plan
support, and behavior on connection failure mid-apply.

The integration check (see "Integration check" above) already does the
scp + `/import` half of this non-interactively against a CHR VM, without
`/safe-mode` — a working reference for the transport, not an apply
implementation.

### Multi-router / flake shape

`evalConfig { modules }` is already the right per-router unit (see
"Settled" above). Expected to extend to something like:

```nix
routnixConfigurations = {
  homeRouter = routnix.lib.evalConfig { modules = [ ./hosts/home-router.nix ]; };
};
```

plus flake plumbing (`packages.<system>."rsc-<name>"`, later
`apps.<system>."activate-<name>"`) once the apply mechanism exists. No
rework of `lib/` anticipated; `specialArgs` (a standard `evalModules`
feature) is the expected mechanism if per-router identity ever needs to be
threaded into modules, but this hasn't been needed yet.
