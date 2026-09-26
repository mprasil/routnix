# Context

Some RouterOS tables only care about presence, not position (routes,
address-lists, VLANs): an entry either exists or it doesn't, and order is
irrelevant.

# Decision

`kind = "unordered"` derives identity automatically from each item's own
fields — no `find` option, and no escape hatch yet to override it. A field
some items set and others don't renders as `!k` (RouterOS's "this field
isn't set") for the items that omit it, so items aren't made
indistinguishable by an elided field.

`create` (`item -> str`, raw `.rsc` text) defaults to a plain `add` of the
item's own fields, which is normally all this kind needs.

Existing entries this path doesn't currently declare are always removed.
Each declared item's id is resolved via `find` (if it already exists) or
`add` (if not) and recorded in a per-path list; `ignore` (predicates OR'd
together) resolves to ids the same way, for entries managed by hand or by
another tool. A `foreach` over the path's existing entries at apply time
then removes anything whose id is in neither list.

Updating an existing match's other fields when they've drifted from the
declared item (full find-then-upsert) is not covered by this decision —
see [`../rfc/unordered-update-if-differs.md`](../rfc/unordered-update-if-differs.md).
