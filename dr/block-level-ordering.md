# Context

`routeros.config` orders whole paths against each other, but real configs
often need several independent, named chunks contributing to the *same*
path, each ordered relative to the others -- finer than "whole path" but
coarser than "every single item" (e.g. a baseline accept rule, then
service-specific rules, then a final catch-all drop in `/ip firewall
filter`).

# Options considered

- Whole paths only: `routeros.config` entries are the only thing
  `before`/`after` can order against each other.
- Named blocks within a resource, ordered against each other by
  `before`/`after` (block names), with the resource's whole item list
  emitted in that order.
- The above plus promoting a block reference that points at a block in
  another resource into a whole-resource-level edge, so ordering can
  cross resources too.

# Decision

A resource's items may be contributed by named, orderable blocks that
sort among themselves by `before`/`after`, referencing other block names.
The resource stays the atomic unit of emission: all of a path's blocks are
emitted together, in block order, as that path's `items`.

Cross-resource ordering is not adopted: `before`/`after` reference block
names only, never paths, and blocks only order items within the same path.
Ordering a whole path against another stays the job of that path's own
`before`/`after`. Block names are unique within their path (they are
attrset keys).

Implemented by the `firewall.filter` module: its `rules` option holds named
blocks (`chain`, `rules`, `before`, `after`) that compile down to the
`items` of `routeros.config."/ip firewall filter"`, ordered by
[`lib/toposort.nix`](./dependency-ordering-toposort.md) the same way paths
are.