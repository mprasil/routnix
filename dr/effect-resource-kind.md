# Context

Some RouterOS entries are realized via one or more commands that aren't a
plain `add` of the item's own fields — e.g. `/user ssh-keys`, where
creating a key requires writing a file first and then running `import`.

# Decision

`kind = "effect"` requires an explicit `find` (`item -> attrsOf
itemValueType`) and lets `create` return arbitrary `.rsc` text instead of
relying on a default `add`:

```nix
routeros.config."/user ssh-keys" = {
  kind = "effect";
  find = item: { user = item.user; };
  create = item: ''
    /file add name="${item.user}.pub" contents="${item.key}"
    import public-key-file="${item.user}.pub" user="${item.user}"
  '';
  items = [ { user = "admin"; key = "ssh-rsa AAAA..."; } ];
};
```

It uses the same `find`-guarded per-item model and `ignore`-guarded
pruning as `"unordered"` (see
[`resource-kind-taxonomy.md`](./resource-kind-taxonomy.md)), but id
resolution differs: `"unordered"`'s `create` defaults to a plain `add`,
whose return value is captured directly as the id, but `"effect"`'s
`create` can run arbitrary commands with no such guarantee (`import`, in
the example above, doesn't hand back an id the way `add` does). Instead,
once `create` has run, `find` is re-resolved to pick up the id — erroring
out if that still finds nothing (a `create` that doesn't leave behind an
entry `find` recognizes would otherwise get silently removed by the same
apply's prune sweep, or go on rerunning every time) or more than one match
(ambiguous).

`create`'s text runs under the entry's own path context; a line can
temporarily target a different absolute path (e.g. `/file add ...`)
without losing that context for subsequent lines, since RouterOS itself
treats a fully-qualified one-line command as a one-off, not a permanent
context switch — routnix doesn't need its own path-tracking mechanism for
this.

This is distinct from the still-unimplemented "unmanaged" idea (see
[`../rfc/unmanaged-resource-kind.md`](../rfc/unmanaged-resource-kind.md))
— `"effect"` is for resources that *are* created via a command, just not
`add`.
