# Context

Not every RouterOS path behaves the same way — some are position-sensitive
tables, some are presence-only tables, some are singleton config objects,
and some require commands other than a plain `add` to realize an entry.
Treating all of them uniformly via a single per-item find-then-upsert
strategy doesn't fit all of these.

# Options considered

- Treat every `routeros.config` entry uniformly, with one reconciliation
  strategy for all paths.
- Require each entry to declare an explicit `kind`, defaulting to one
  strategy when unset.
- Require each entry to declare an explicit `kind`, with no default.

# Decision

Every `routeros.config` entry declares a required `kind`:
`"ordered"`, `"unordered"`, `"settings"`, or `"effect"` — see
[`ordered-resource-kind.md`](./ordered-resource-kind.md),
[`unordered-resource-kind.md`](./unordered-resource-kind.md),
[`settings-resource-kind.md`](./settings-resource-kind.md), and
[`effect-resource-kind.md`](./effect-resource-kind.md) for each kind's own
reconciliation semantics. There is no default: picking a kind is a
meaningful decision about how RouterOS treats that table, not something
safe to fall back on.

For every kind except `"settings"`, `find` (explicit or derived, depending
on the kind) must actually distinguish items from each other: rendering
throws if two items in the same `items` list produce the same `find`
result, rather than letting them silently collapse into a single RouterOS
entry instead of two.
