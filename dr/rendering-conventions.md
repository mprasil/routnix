# Context

Rendering `routeros.config` to `.rsc` text needs consistent conventions for
scalar values, fields some items don't set, paths with nothing to render,
and ordering within a rendered line vs. within a declared list.

# Decision

- `bool` renders as `yes`/`no`; `int`/`str` render double-quoted (`"22"`,
  not `22`) — shared by every kind's rendering, `find`'s query, and
  `create`'s default body.
- A field only some items in a list set renders as `!k` (RouterOS's "this
  field isn't set") for the items that omit it, rather than being left out
  of the query — used by `find`'s rendered query and by
  `"unordered"`/`"ordered"`'s derived identity (see
  [`unordered-resource-kind.md`](./unordered-resource-kind.md)), so
  items aren't made indistinguishable by an elided field.
- A `"settings"` entry with empty `settings`, and an `"inventory"` entry
  with empty `items`, render nothing but a `preScript`, if it has one, and
  never a path header. The table kinds (`"ordered"`/`"unordered"`/`"effect"`)
  always emit the path header and run their mandatory prune sweep, even
  with an empty `items` list (see `checks/configs/*_prune_empty.nix`).
- Field order *within* one rendered line follows Nix's `attrsOf` iteration
  (alphabetical), since it doesn't matter to RouterOS. Item *list* order is
  always preserved exactly as declared, since that's what matters for
  order-sensitive (`"ordered"`) tables.
- A failing guard `:put`s its human-readable message, on its own line,
  before aborting with `:error`, whose argument is a short, code-like
  marker (e.g. `routnix-find-matched-multiple-entries`), not that message.
  RouterOS may report `:error`'s own text only in the log rather than the
  console (notably on v6), so a message passed to `:error` alone wouldn't
  reliably reach the user.
