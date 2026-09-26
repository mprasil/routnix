# Context

Some RouterOS entries are bound to the hardware or firmware they run on —
physical interfaces, system packages — so they exist or don't depending on
the device, and routnix can neither create nor remove them. It still needs
to adjust aspects of the ones that are present: rename an interface, set an
interface parameter, enable or disable a package.

# Decision

`kind = "inventory"` is for entries routnix adjusts in place but never adds
or removes. It isn't modeled as `"effect"`, which expects `create` to bring
a new entry into existence and always prunes entries no longer declared
(see [`effect-resource-kind.md`](./effect-resource-kind.md)) — inventory
entries always already exist and must never be created or pruned. It
requires an explicit `find` (like `"effect"`) and a `configure` function
returning arbitrary `.rsc` text (like `"effect"`'s `create`, but acting on
an entry that already exists):

```nix
routeros.config."/system package" = {
  kind = "inventory";
  find = item: { name = item.name; };
  configure = item: if item.enable then "enable $item" else "disable $item";
  items = [
    { name = "ipv6"; enable = true; }
    { name = "mpls"; enable = false; }
  ];
};

routeros.config."/interface ethernet" = {
  kind = "inventory";
  find = item: { "default-name" = item.defaultName; };
  configure = item: "set $item name=${item.name}";
  items = [{ defaultName = "ether1"; name = "lan1"; }];
};
```

In practice, for each item:

- `find` resolves the item to its existing entry, exactly one (`>1` is an
  error, as for the other kinds). `$item` is bound to that resolved entry,
  so `configure` refers to it directly rather than repeating the `find` —
  the `:local item [ ... find where ... ]; enable $item` shape.
- `configure`'s text runs under the entry's own path context, and, as for
  `"effect"`, a line can target a different absolute path without losing
  that context for the following lines.
- A `find` that matches nothing is a hard error, not a skip: a declared item
  that isn't present is almost always a typo or a stale declaration, and
  failing loudly surfaces it instead of silently doing nothing. Conditional
  presence (an interface or package that only some devices have) is handled
  at eval time, by not declaring the item on those devices.

There is no pruning, so nothing at the path is ever removed and no ownership
information is needed — nothing is ever claimed
(see [`../rfc/ownership-identity-tagging.md`](../rfc/ownership-identity-tagging.md)).
`ignore` has no meaning here and is ignored. Because no prior state is
tracked, adjusting an entry only converges it to the declared value:
dropping a `name` change from the config doesn't restore the old name; it
would be set to another value instead.