# Context

`routeros.config` paths need to be ordered relative to each other based on
declared `before`/`after`, with cycles reported clearly instead of looping
forever or producing garbage output.

# Options considered

- An external DAG library (e.g. `denful/dag`).
- nixpkgs' `lib.textClosureList`.
- nixpkgs' built-in `lib.toposort`.

# Decision

`lib/toposort.nix` is a thin wrapper around nixpkgs'
`lib.lists.toposort :: (a -> a -> Bool) -> [a] -> { result } | { cycle, loops }`.
No external dependency is used — `lib.toposort` already gives structured
cycle detection, which is all that was needed from either alternative
originally considered.

The comparator:

```nix
precedes = a: b:
  builtins.elem b routerosConfig.${a}.before || builtins.elem a routerosConfig.${b}.after;
```

i.e. `a` must render before `b` if `a` lists `b` in `before`, or `b` lists
`a` in `after`. On a cycle, `sortEntries` throws a message naming the cycle
and where it loops back to.
