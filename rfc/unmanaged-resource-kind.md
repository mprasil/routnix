# Context

Some RouterOS entries are hardware-bound and can't be created or
destroyed — physical interfaces, wifi radios. These need to be configured
(via `set`) but never added, removed, or pruned the way the existing kinds
are, since nothing about them is ever "claimed" by routnix.

# Options considered

## Model via `kind = "effect"`

Reuse `"effect"`'s `find` + arbitrary-`create` machinery, since it already
supports commands other than a plain `add`
(see [`../dr/effect-resource-kind.md`](../dr/effect-resource-kind.md)).
Doesn't fit well: `"effect"` still expects `create` to bring a new entry
into existence and participates in mandatory pruning, whereas these
entries always already exist and must never be pruned.

## A new `"unmanaged"` kind

A kind for entries identified by their real native name, only ever `set`,
never added, removed, or pruned, with no ownership tag needed since
nothing is ever claimed. Not designed further yet — a concrete example is
needed before designing this one further.
