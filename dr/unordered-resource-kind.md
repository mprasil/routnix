# Context

Some RouterOS tables only care about presence, not position (routes,
address-lists, VLANs): an entry either exists or it doesn't, and order is
irrelevant.

# Decision

`kind = "unordered"` derives identity automatically from each item's own
fields — no `find` option to override it. A field some items set and others
don't renders as `!k` (RouterOS's "this field isn't set") for the items that
omit it, so items aren't made indistinguishable by an elided field. A table
whose identity is a strict subset of its fields is covered by `"keyed"`
instead (see [`keyed-resource-kind.md`](./keyed-resource-kind.md)).

`create` (`item -> str`, raw `.rsc` text) defaults to a plain `add` of the
item's own fields, which is normally all this kind needs.

Existing entries this path doesn't currently declare are always removed.
Each declared item's id is resolved via `find` (if it already exists) or
`add` (if not) and recorded in a per-path list; `ignore` (predicates OR'd
together) resolves to ids the same way, for entries managed by hand or by
another tool. A `foreach` over the path's existing entries at apply time
then removes anything whose id is in neither list.

Updating an existing match's other fields when they've drifted from the
declared item (full find-then-upsert) is not covered by this decision: an
existing match is left alone. A table that needs an existing entry updated
or replaced, or whose identity is a subset of its fields, uses `"keyed"`
instead (see [`keyed-resource-kind.md`](./keyed-resource-kind.md)).
