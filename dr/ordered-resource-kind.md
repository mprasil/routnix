# Context

Some RouterOS tables are position-sensitive — RouterOS evaluates them
top-to-bottom (firewall filter/mangle/nat, routing rules, queue trees) — so
reordering declared items must actually reorder them on the router, not
just ensure they're all present.

# Options considered

- Remove every managed entry and re-add them in the declared order on
  every apply.
- Resolve each item in turn — adding missing ones already placed as close
  to their declared position as possible — then a final pass that fixes
  any drifted positions.

# Decision

`kind = "ordered"` reconciles incrementally in two phases, threading a
`$managed` list of resolved ids across items via a shared per-path scope.
Remove-all-then-readd was ruled out: it drops rule counters and
connection-tracking state, and momentarily leaves the resource unprotected.

Identity has no `find` option; like `"unordered"`, it's derived
automatically from each item's own fields.

Phase 1 resolves each item in turn, in a fresh scope per item: a missing
item is `add`-ed already placed via `place-before=` — the first declared
item targets whatever currently sits at the top of the table (or is added
plainly if the path is empty), every other item targets `.nextid` of the
*previous* declared item's just-resolved id. This places a freshly-created
item correctly without waiting on phase 2.

Phase 2 walks `$managed` once more and `move`s anything not already
immediately following its predecessor — the one case add-time placement
can't cover: an already-present item repositioned since the last apply by
something other than routnix.

Both phases target *immediate* adjacency to the previous declared item, so
declared items end up contiguous — unlike `"unordered"`, a foreign entry
interleaved between two declared items doesn't survive reapplying; it gets
pushed out of the gap.

Pruning is mandatory, not optional: since identity is the whole item, any
field edit makes the previous version of that item stop matching, leaving
it behind as an unmanaged duplicate once the edited item is re-added.
routnix always sweeps up anything not in `$managed` or `ignore` to avoid
accumulating these.
