# Context

Some presence-only tables have an identity that is a strict subset of their
fields, and RouterOS refuses a second entry with the same identity: a bridge
is identified by `name`, and a bridge port by `interface` (adding another
port for the same interface fails with `device already added as bridge
port`). `"unordered"` derives identity from every field, so an item that
sets any extra field, or omits one another item sets (rendered as `!k`),
stops matching an existing entry; it then tries to `add` and fails on the
duplicate identity. It also can't clear a field that was declared before and
isn't now, since RouterOS has no generic way back to a default.

# Decision

`kind = "keyed"` is for presence-only tables with an explicit identity and
settable attributes:

```nix
routeros.config."/interface bridge port" = {
  kind = "keyed";
  key = item: { interface = item.interface; };
  items = [
    { bridge = "home-lan"; interface = "ethernet1"; }
    { bridge = "home-lan"; interface = "ethernet2"; priority = 10; }
  ];
};
```

`key` (`item -> attrsOf itemValueType`, required) is the stable identity
used to locate an existing entry: `{ name = item.name; }` for a bridge,
`{ interface = item.interface; }` for a port. Identity is not derived from
the item's fields as for `"unordered"`, and there is no `find` or `create`:
items are created with a plain `add` of their own fields.

Every entry routnix creates is tagged in `comment`:

```
comment = "routnix:<shape>:<value>" + (" " + <user comment>  if any)
```

- `shape` is a short hash of the sorted set of the item's field names.
- `value` is a short hash of the item's rendered field values, the user
  comment text included, the tag itself excluded.

`comment` is used because it has no RouterOS default, so `!comment` and
prefix matching on it are reliable where `!field` for a defaulted field is
not: RouterOS treats a default value as set, so `!priority`, `!mtu` and the
like never match an existing entry.

Reconciling one item:

1. Locate an existing entry by `key`; more than one match is an error, as
   for the other kinds.
2. No match: `add` the item with its tag.
3. The stored `comment` equals the expected tag (plus user comment): already
   in sync, nothing to do.
4. It matches `^routnix:<shape>:`: same field set, values drifted: `set`
   the declared fields and the tag.
5. Otherwise (the field set changed, or the entry is foreign or untagged):
   `remove` it and `add` a fresh one with the tag.

Pruning is mandatory and unscoped, as for the other table kinds: entries
neither declared nor covered by `ignore` are removed, tagged or not.
`ignore` (predicates OR'd together, like `"unordered"`) is the escape hatch
for entries routnix shouldn't touch, including dynamic entries on a path
that has them: a higher-level module covers those with
`ignore = [{dynamic = true;}]`, so the kind itself needs no knowledge of
`dynamic`. An ignored entry that occupies a declared `key` is an error --
the key is unique, so routnix has nowhere to add its own entry.

Splitting the tag into `shape` and `value` keeps a steady-state apply a
no-op and confines disruption to real edits: a value tweak (a bridge's
`mtu`, a port's `priority`) is a `set` with no link flap, while a changed
field set is a remove-and-re-add, the only way to return a dropped field to
its default. Because sync is decided by comparing the stored tag against a
Nix-computed hash, no read-back-versus-declared comparison is needed and
RouterOS's value normalization (hex vs decimal, `yes`/`no`, quoting) is
irrelevant. Since lookup is by `key`, a hash collision between two items is
unlikely to be a problem, so the hashes stay short.

A path without a writable `comment` field can't use this kind and uses
another one instead. Out-of-band edits to a managed entry aren't detected
(the tag is unchanged), and a foreign entry occupying a declared key is
replaced; both are accepted, the same way `"unordered"` treats them.

This is the first kind to write a synthetic tag into `comment`; whether the
kinds that predate it adopt one too is still open (see
[`../rfc/ownership-identity-tagging.md`](../rfc/ownership-identity-tagging.md)).
