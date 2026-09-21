# Context

Identity (how an existing entry is matched, e.g. via `find`) and ownership
(how routnix knows an entry is actually safe to update, reposition, or
remove because it created it) are deliberately separate concerns. Today,
`find`/derived identity matches on value alone, with no ownership tag, so
routnix can't distinguish "an entry we created" from "an entry that
happens to match."

# Options considered

## Match on value alone (current behavior)

`find`/derived identity as implemented today for all of `"unordered"`,
`"ordered"`, and `"effect"` (see their respective `dr/` files). Mandatory
pruning removes anything not in `$managed` or `ignore`, with `ignore` as
the only escape hatch — an approximation of ownership, not the real thing.
Risk: a coincidentally-matching pre-existing entry (a dynamic lease, a
manually-added rule) can be silently treated as "already there," updated,
repositioned (for `"ordered"`), or pruned, even though routnix never
created it. No silent "adoption" is *intended*, but nothing enforces that.

## Synthetic ownership tag written into `comment`

Default identity/lookup mechanism becomes a tag (e.g.
`routnix:<block>:<name>`) written into `comment`, with any user-supplied
comment text appended after it, decoupled from whichever real fields the
item actually sets. Avoids baking an ownership prefix into whatever field
is used as the lookup key, which breaks down when that field is a real,
semantically constrained value rather than free text with room for a
prefix. Would let pruning and adoption-avoidance be precise instead of
relying on the caller's `ignore` list to enumerate every un-owned entry by
hand. Whatever the identity mechanism ends up being, `find`'s query should
additionally require the tag to be present wherever possible, so matching
by value alone never silently "adopts" an entry.

## Natural, composite-field identity (escape hatch)

For resources without a usable `comment` field, or where a synthetic tag
isn't wanted: match on a combination of real fields the entry already sets
(e.g. `address` + `list` together for address-lists, since an address
alone isn't unique across lists). This is the *only* mechanism implemented
today — `kind = "effect"`'s required `find`, and `"unordered"`/`"ordered"`'s
automatically-derived identity, both match on value/composite fields, with
no synthetic tag involved yet.

Not decided: exact tag format, whether the prefix is globally
configurable, and whether adoption of pre-existing entries should be a
deliberate opt-in feature regardless of which identity mechanism wins.
