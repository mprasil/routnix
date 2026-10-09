# Context

Identity (how an existing entry is matched) and ownership (how routnix knows
an entry is safe to update, reposition, or remove because it created it) are
separate concerns. The `"keyed"` kind (see
[`../dr/keyed-resource-kind.md`](../dr/keyed-resource-kind.md)) writes a
synthetic `routnix:<shape>:<value>` tag into `comment`, which it uses to tell
an already-in-sync entry from a drifted or foreign one, but its pruning is
unscoped like the other table kinds': anything neither declared nor
`ignore`d is removed, so the tag does not make pruning ownership-precise.
The kinds that predate it — `"unordered"`, `"ordered"`, and `"effect"` —
have no tag at all, matching on value or composite fields, with `ignore` as
the only protection.

# Options considered

## Prune unscoped, `ignore` as the escape hatch (current)

Every table kind removes anything neither declared nor `ignore`d, and relies
on `ignore` to protect entries managed by hand or by another tool. Uniform
and predictable, but a coincidentally-matching pre-existing entry (a dynamic
lease, a manually-added rule) can be silently adopted, updated, repositioned
(`"ordered"`), or pruned even though routnix never created it, and `ignore`
has to enumerate every such entry by hand.

## Make pruning ownership-precise via the tag

Have kinds whose paths carry a `comment` write the `routnix:` tag and prune
only tagged entries, leaving untagged entries alone by default. Removes the
need for `ignore` to enumerate un-owned entries. Costs: two different prune
semantics (tagged vs not), a writable `comment` requirement that not every
path meets, and no help for paths whose identity is a real, semantically
constrained field rather than free text. `"keyed"` deliberately does not do
this today.

Not decided: whether ownership-precise pruning is worth the divergence, and
what to do for paths with no usable `comment` field.
