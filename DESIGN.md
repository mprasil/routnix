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
modules/routeros.nix    -- the evalModules options (RouterOS-specific)
lib/toposort.nix         -- before/after -> ordered list, via lib.toposort
lib/render_rsc.nix       -- ordered routeros.config -> .rsc text
lib/default.nix          -- glue: evalConfig { modules } -> evaluated config + .rsc
examples/basic.nix       -- example config
examples/cycle.nix       -- example that intentionally triggers a cycle error
flake.nix                -- exposes packages.<system>.example (built .rsc)
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
      find    = mkOption { type = types.functionTo (types.attrsOf itemValueType); };
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

`routeros.config` is keyed by **full RouterOS path, including the leading
slash** (e.g. `"/ip/firewall/filter"`), matching idiomatic RouterOS
scripting syntax (RouterOS accepts `/`-separated paths as equivalent to the
more commonly documented space-separated form).

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
  rules, queue trees). `find` (same shape as `"unordered"`, see below)
  locates each item; missing items are `add`-ed and present-but-misplaced
  ones are `move`-d, so reapplying neither duplicates entries nor
  disturbs ones already correctly placed, e.g.:

  ```nix
  routeros.config."/ip/firewall/filter" = {
    kind = "ordered";
    find = item: { comment = item.comment; };
    items = [
      { chain = "input"; action = "accept"; protocol = "icmp"; comment = "allow-icmp"; }
      { chain = "input"; action = "drop"; comment = "drop-rest"; }
    ];
  };
  ```

  Correctness only means declared items stay in declared order *relative
  to each other* — entries `find` doesn't match (foreign or unmanaged
  ones) can sit interleaved among them untouched. For each item, in a
  fresh script scope, rendering resolves `dest` to the id of the nearest
  declared item *after* it that already exists (trying each in turn, at
  apply time, since Nix has no visibility into router state at eval
  time), then either `add`s the item (via `place-before=$dest` if
  resolved) or, if it's already present, `move`s it to `dest` only if it
  doesn't already come after the previous item. This replaced an earlier
  remove-all-then-readd idea, ruled out for dropping rule counters and
  connection-tracking state and momentarily leaving the resource
  unprotected.

- **`"unordered"`** — presence, not position, matters (routes,
  address-lists, VLANs). Each item is only `add`-ed if `find` doesn't
  already match an existing entry:

  ```nix
  routeros.config."/ip/firewall/address-list" = {
    kind = "unordered";
    find = item: { address = item.address; list = item.list; };
    items = [ { address = "192.168.1.0/24"; list = "trusted-ips"; } ];
  };
  ```

  `find` is `item -> attrsOf itemValueType`, rendered as
  `print count-only where k=v ...` (compared against `0`, rather than
  `find where ...` compared against `""` — a plain count sidesteps how
  `find` behaves when a query matches more than one entry), and is
  **required** — there's deliberately no "always add unconditionally"
  default, since that would silently duplicate entries on reapply.
  `create` (`item -> str`, raw `.rsc` text) defaults to a plain `add` of
  the item's own fields, which is normally all this kind needs.

  Optionally, `prune = true` removes existing entries this path doesn't
  currently declare — rendered as a `foreach` over the path's existing
  entries at apply time (Nix has no visibility into router state at eval
  time), removing anything not matched by `find` for any current item.
  Off by default, since removing entries is destructive. `ignore` (a list
  of field predicates, OR'd together) exempts entries from pruning
  regardless of `items` — e.g. for entries managed by hand or by another
  tool. Only valid for `kind = "unordered"`; setting `prune` on any other
  `kind` is an error. This only approximates ownership (see "Ownership and
  identity" below) — an entry that happens to match neither `ignore` nor
  any current `find` is removed even if routnix never created it.

- **`"settings"`** — a non-table, singleton config object (e.g.
  `/ip/dhcp-server/config`). `settings` (a single `attrsOf itemValueType`,
  not a list) is rendered as one `set` of all declared fields — inherently
  idempotent, no `items`/`find`/`create`/identity/ordering involved.

- **`"effect"`** — items realized via one or more RouterOS commands that
  aren't a plain `add` of the item's own fields, e.g. `/user/ssh-keys`,
  where creating a key requires writing a file first and then running
  `import`:

  ```nix
  routeros.config."/user/ssh-keys" = {
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

  This is distinct from `DESIGN.md`'s original "unmanaged" idea (below) —
  hardware-bound entries identified by native name, only ever `set` — which
  remains unimplemented and un-named; `"effect"` is for resources that
  *are* created via a command, just not `add`.

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

- `"ordered"`: emit `<path>` then, per item, a scoped reconciliation
  block:
  ```
  {
    :local dest ""
    :if ($dest = "") do={ :set dest [<path> find where k=v ...] }   -- one per later declared item, first existing one wins
    :local id [<path> find where k=v ...]
    :if ($id = "") do={
      add [place-before=$dest] k=v ...
      :set id [<path> find where k=v ...]
    } else={
      :if ($anchor != "") do={
        :local ok false
        :foreach j in=[<path> find] do={
          :if ($j = $anchor) do={ :set ok true }
          :if ($j = $id) do={ :if (!$ok) do={ move $id [destination=$dest] } }
        }
      }
    }
    :set anchor $id
  }
  ```
  built from `find item` for both this item's own identity and (as a
  fallback chain) each later item's. `$anchor` (the previous item's id)
  is carried across items via a shared, per-path scope opened by
  `:local anchor ""` before the first item's block.
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
- `"settings"`: emit `<path>` then a single `set k=v k=v ...` line built
  from the `settings` attrset.

For `"unordered"` entries with `prune = true`, an additional block follows
the guards, per path:
```
:foreach i in=[<path> find] do={
  :local ignored false
  :if ([<path> get $i k]=v ...) do={ :set ignored true }   -- one per `ignore` predicate
  :local keep false
  :if ([<path> get $i k]=v ...) do={ :set keep true }      -- one per current item's `find`
  :if (!$ignored and !$keep) do={ <path> remove $i }
}
```
Built as `:if`/`:foreach` script logic rather than a single composed
`where` query, since RouterOS's `where` mini-language doesn't reliably
document boolean composition (`or`, grouped negation) across many
conditions, whereas `:if`'s conditional syntax is the same well-documented
mechanism already used for the guard blocks above.

Entries that render to nothing (empty `items`/`settings`, and no `prune`)
are skipped entirely. Scalar value rendering rules (shared by all of the
above, and by `find`'s query and `create`'s default body):

- `bool` → `yes` / `no`
- `int` → bare (`22`, not `"22"`)
- `str` → double-quoted

Field order *within* one rendered line is whatever Nix's `attrsOf`
iteration gives us (alphabetical) — this doesn't matter to RouterOS. Item
*list* order is preserved exactly as declared, which is what matters for
order-sensitive (`"ordered"`) tables.

### `evalConfig` (`lib/default.nix`)

```nix
evalConfig { modules }:
  -- evaluates `modules` (plus modules/routeros.nix) via lib.evalModules,
  -- topologically sorts config.routeros.config,
  -- returns the evalModules result plus an `rsc` attribute with the
  -- rendered, ordered .rsc text.
```

This is the per-router unit of evaluation: one call = one router's config +
rendered script. See "Multi-router / flake shape" below for how this is
expected to extend to managing several routers from one flake — no rework
anticipated there, just wrapping multiple calls to this function.

## Open design space

Everything below is unresolved. It's recorded here so we don't have to
reconstruct the reasoning from scratch, not as a decision.

### Block-level ordering

`routeros.config` currently orders whole paths against each other. Real configs
(the motivating example being `/ip/firewall/filter`) often need several
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
  top-to-bottom. **Settled and implemented**: find-by-identity (`find`,
  required, same shape as `"unordered"`) plus incremental reconciliation
  via `add`/`add place-before=` and `move` (see "Resource kinds" above) —
  not remove-all-then-readd, which was ruled out for dropping rule
  counters and connection-tracking state and momentarily leaving the
  resource unprotected. **Still open**: like `"unordered"`,
  update-if-differs isn't implemented (a present, correctly-placed item is
  left alone even if its other fields drifted); and the ownership gap
  described below (`find` matches on value alone) applies here too.
- **`"unordered"` / keyed** tables (address-lists, DHCP static leases, IP
  pools) — order doesn't matter. **Settled:** find-by-identity (`find`,
  required per entry) then `add` only if missing (`create`, defaulting to
  a plain `add` of the item's own fields). **Still open:** update-if-differs
  is not implemented — an existing match is left alone even if its other
  fields have drifted from the declared item, so this isn't yet full
  find-then-upsert.
- **`"settings"`** (non-table, singleton config objects — e.g.
  `/ip/dhcp-server/config`) — **settled and implemented**: a single `set`
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
(attrset-keyed) shape. Identity for `"unordered"`/`"effect"` comes from the
required `find` function, not from list vs. attrset structure.

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
**Settled and implemented** as `kind = "unordered" | "effect"`'s required
`find` (`item -> attrsOf itemValueType`, rendered as
`print count-only where k=v ...`, compared against `0`)
— every such entry states its own identity explicitly, composite or not.
Deliberately required rather than defaulting to an "always add
unconditionally" fallback, since that would silently duplicate entries on
reapply.

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

`kind = "ordered"`'s `find`-based `place-before`/`move` reconciliation
(see "Resource kinds" above) was implemented without waiting on this —
it matches on value alone, same as `"unordered"`/`"effect"`, so a
coincidentally-matching foreign entry could be misidentified as a
declared item's position anchor and moved. This is accepted for now as
the same adoption risk already noted above, just applied to positioning
instead of update/prune — not solved by a tag-based mechanism, if one
lands later.

**Partially settled and implemented** for `kind = "unordered"`:
stale-entry cleanup via `prune`/`ignore` (see "Resource kinds" above) —
but as an approximation of ownership, not the tag-based mechanism
discussed above. `prune` removes anything not matched by a current item's
`find` and not covered by `ignore`, with no notion of "entries we created"
distinct from "entries that happen to match" — so it inherits the same
adoption risk noted above, applied to deletion instead of update: an
entry `routnix` never created can still be pruned if it isn't declared and
isn't explicitly `ignore`d. A tag-based ownership mechanism, if it lands
later, would let pruning (and adoption-avoidance generally) be precise
instead of relying on the caller's `ignore` list to enumerate every
un-owned entry by hand.

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
