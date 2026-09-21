# Context

`routeros.config` currently orders whole paths against each other. Real
configs (the motivating example being `/ip firewall filter`) often need
several independent, named chunks contributing to the *same* path, each
ordered relative to each other (e.g. baseline accept rules, then a rule
that depends on an address-list existing, then a final catch-all drop) —
finer than "whole path" but coarser than "every single item."

# Options considered

## Split into blocks and resources, with two independent orderings

Named, orderable "blocks" contribute items to a "resource" (a path, which
stays the atomic unit of *emission*). Two independent orderings:

1. Blocks belonging to the same resource, ordered against each other via
   `beforeConfigs`/`afterConfigs` referencing other block names.
2. Resources ordered against each other, derived automatically by taking
   each block's `beforeConfigs`/`afterConfigs` references that point at a
   block belonging to a *different* resource, and promoting them to a
   resource-level edge — since all of a resource's blocks are emitted
   together atomically, "block A before block B" where B is in another
   resource necessarily means "A's whole resource before B's whole
   resource."

Cross-resource ordering can only be expressed at this promoted,
whole-resource granularity: a block cannot be ordered relative to a single
item in another resource, because all items of a resource are emitted as
one atomic unit.

Also unresolved under this option: whether block names need to be
**globally unique** across the whole config (not just within their
resource), since references would be bare names looked up in a flat
namespace; and how `"settings"` merges when contributed by multiple
blocks — leaning towards plain attrset union, but this is only "open"
because blocks don't exist yet, not because a real alternative is being
weighed.

## Keep a separate beforeResources/afterResources field

Alongside the block-level mechanism above, add an explicit field for
ordering whole resources directly, instead of (or in addition to)
promoting a block-level reference. Referencing one block is enough to pull
in a dependency on its entire resource once promoted (previous option),
but that trades off reading as depending on an arbitrary "representative"
block rather than the resource itself.

Not decided whether to keep both mechanisms or unify on one.
