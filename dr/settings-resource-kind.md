# Context

Some RouterOS config is a non-table, singleton object (e.g.
`/ip dhcp-server config`) rather than a list of independent entries.

# Decision

`kind = "settings"` takes a single `settings` attrset (not a list),
rendered as one `set` of all declared fields. It's inherently idempotent,
so no `items`, `find`, `create`, identity, or ordering is involved.
