# Context

Some RouterOS config is a non-table, singleton object (e.g.
`/ip dhcp-server config`) rather than a list of independent entries.

# Options considered

- Model singleton config the same way as table kinds, e.g. an `items` list
  constrained to length 1.
- A dedicated kind holding a plain attrset of fields, with no
  identity/ordering machinery at all.

# Decision

`kind = "settings"` takes a single `settings` attrset (not a list),
rendered as one `set` of all declared fields. It's inherently idempotent,
so no `items`, `find`, `create`, identity, or ordering is involved.
