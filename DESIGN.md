# routnix — design notes

This document is a running reference for the design of `routnix` ("router"
+ "nix"): declarative router/network-device configuration using the Nix
module system, in the spirit of [`mikrotik.nix`](https://github.com/nrabulinski/mikrotik.nix)
but implemented entirely in Nix.

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

## Motivation, and what we take from `mikrotik.nix`

`mikrotik.nix` demonstrated a shape we like:

- Options/config expressed via a Nix module system (`lib.evalModules`),
  including a freeform low-level DSL that maps closely to RouterOS's own
  path/field structure.
- The end product is a `.rsc` script, applied to the router over SSH by
  copying it over and running `/import`.

What we want to do differently:

- No Rust. The `mikrotik.nix` reference implementation does ordering and
  `.rsc` rendering in a separate Rust binary (`json-to-rsc`, using
  `petgraph` for topological sort) that consumes JSON produced from the
  evaluated Nix config. We want the entire pipeline — module evaluation,
  dependency ordering, and rendering — to be plain Nix, evaluated lazily,
  with no external tool/build step in between.
- Ordering that's correct for RouterOS's positional tables (see
  "Ordered vs. keyed resources" below), which `mikrotik.nix` doesn't
  currently model — reordering firewall rules in its DSL does not reorder
  them on the router, since it always does per-key upsert regardless of
  whether the underlying table is order-sensitive.
- A clearer split between *identity* (how we find/match an entry) and
  *ownership* (how we know an entry is ours to manage), so that ownership
  tracking doesn't have to be smuggled into whatever field happens to be
  used as the lookup key (see "Ownership and identity" below).

## Settled: current implementation

### Repo layout

```
modules/routeros.nix    -- the evalModules options (RouterOS-specific)
lib/toposort.nix         -- before/after -> ordered list, via lib.toposort
lib/render.nix           -- ordered routeros.config -> .rsc text
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
      before = mkOption { type = types.listOf types.str; default = [ ]; };
      after  = mkOption { type = types.listOf types.str; default = [ ]; };
      items  = mkOption {
        type = types.listOf (types.attrsOf (types.oneOf [ types.bool types.int types.str ]));
        default = [ ];
      };
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
entry per RouterOS path, an ordered list of `add`-able items, and
`before`/`after` to declare ordering relative to *other whole paths*. There
is currently no concept smaller than "a whole path" — see "Block-level
ordering" below for the finer-grained model we discussed but haven't built.

Item values are intentionally loosely typed (`bool | int | str`) — see
"Typing" below for why we're not modeling RouterOS's per-field value syntax
more strictly at this layer.

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

### Rendering (`lib/render.nix`)

For each path in dependency order, if it has any `items`, emit:

```
<path>
add k=v k=v ...
add k=v ...
```

paths with no items are skipped entirely. Value rendering rules:

- `bool` → `yes` / `no`
- `int` → bare (`22`, not `"22"`)
- `str` → double-quoted

Field order *within* one `add` line is whatever Nix's `attrsOf` iteration
gives us (alphabetical) — this doesn't matter to RouterOS. Item *list*
order is preserved exactly as declared, which is what matters for
order-sensitive tables.

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

Not every RouterOS path behaves the same way, and treating them uniformly
(as `mikrotik.nix` mostly does, via per-item find-then-upsert) is
insufficient. Distinguished so far:

- **Ordered / positional** tables (firewall filter/mangle/nat, routing
  rules, queue trees) — position matters; RouterOS evaluates these
  top-to-bottom. Per-item upsert-by-key does not preserve position across
  applies. Direction discussed: on apply, remove *all currently-existing
  owned entries* for that resource in one pass, then re-`add` the complete,
  freshly computed, correctly-ordered list in another single pass. This
  must happen as one atomic operation over the resource's *entire* merged
  item set (all contributing blocks combined) — doing it per-block would
  mean a later block's removal pass could delete an earlier block's
  just-added items in the same run, since a removal pass has no way to
  distinguish "not declared anywhere" from "not processed yet." This is
  the reason a resource has to be the atomic unit of emission regardless of
  how fine-grained block-level ordering gets.
- **Keyed / unordered** tables (address-lists, DHCP static leases, IP
  pools) — order doesn't matter; find-by-identity then add-or-update, closer
  to what `mikrotik.nix` already does.
- **Settings** (non-table, singleton config objects — e.g.
  `/ip/dhcp-server/config`) — no entries, no identity/ownership needed at
  all, just a `set` of whatever fields are declared, merged from possibly
  multiple contributing blocks via plain attrset union (conflicting values
  on the same field = error). Trivially idempotent since `set` with an
  already-current value is a no-op. Believed to be the simplest case, not
  an unsolved one.
- **Unmanaged** tables (hardware-bound entries that can't be created or
  destroyed — physical interfaces, wifi radios) — identified by their real
  native name, only ever `set`, never added/removed, no ownership tag
  needed since nothing is ever claimed.

Not decided how a resource declares which of these it is (explicit
per-resource field vs. a built-in registry of well-known RouterOS paths vs.
some other mechanism), nor the exact option shape once blocks exist (e.g.
whether `items` is a list or an attrset depends on ordering — Nix attrsets
don't preserve declaration order when enumerated, so ordered resources
need list-shaped items, while keyed resources are more ergonomic as an
attrset keyed by Nix name).

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
whichever real fields the item actually sets. This sidesteps a real problem
with `mikrotik.nix`'s approach (baking the ownership prefix into whatever
field is used as the key), which breaks when that field is a real,
semantically constrained value rather than free text (`mikrotik.nix` itself
has to special-case this with `_prefix = ""`, giving up tracking for those
resources).

Also discussed: an escape hatch for **natural, composite-field identity**
(e.g. matching address-lists by `address` + `list` together, since an
address alone isn't unique across lists) for cases where a synthetic tag
isn't wanted or isn't available (no `comment` field on that resource).
Whatever identity mechanism is used, the `find` query should still require
the ownership tag to be present wherever possible — matching by value alone
risks silently claiming an entry we didn't create (a coincidentally
matching dynamic lease, a manually-added rule). Consequence: no silent
"adoption" of pre-existing entries in v1 — bringing an existing manually
configured entry under routnix management will produce a visible duplicate
until the old one is removed by hand. Whether adoption should be a
deliberate opt-in feature later is open.

Not decided: exact tag format, whether the prefix is globally configurable
(analogous to `mikrotik.nix`'s `meta.prefix`), and how/whether stale-entry
cleanup (removing tagged entries that are no longer declared) gets
implemented — explicitly deferred per the original scope ("keep this in
mind and implement later").

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

Not yet implemented at all. Direction from `mikrotik.nix` we intend to keep:
scp the rendered `.rsc` to the router, `/import` it, wrapped in RouterOS's
`/safe-mode take` / `release` so a failure rolls back rather than leaving a
half-applied config. Open questions not yet discussed in depth: dry-run/plan
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
