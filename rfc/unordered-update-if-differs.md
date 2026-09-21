# Context

`kind = "unordered"` currently only `add`s a declared item if no existing
entry matches it (see
[`../dr/unordered-resource-kind.md`](../dr/unordered-resource-kind.md)).
It doesn't update an existing match's other fields if they've drifted from
the declared item, so it isn't yet full find-then-upsert.

# Options considered

## Leave add-only (current behavior)

An existing match is left alone even if its other fields differ from the
declared item; only missing items get created. Simpler, but a field that
drifted out-of-band (or was declared differently in a previous version of
the config) stays drifted until the entry is removed and re-added some
other way.

## Implement full find-then-upsert

When `find`/derived identity matches an existing entry, compare its fields
against the declared item and `set` any that differ, in addition to
`add`-ing missing items. Brings `"unordered"` in line with a more
conventional declarative-reconciliation model, at the cost of needing a
field-by-field diff and `set` step per matched item.
