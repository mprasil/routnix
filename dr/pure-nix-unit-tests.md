# Context

`lib/render_rsc.nix`, `lib/toposort.nix`, and `modules/*.nix` need unit
tests that don't require booting a RouterOS VM for every change, and that
pinpoint what a module compiles down to independently of how that gets
rendered.

# Decision

`lib/tests/` exercises `lib/render_rsc.nix`/`lib/toposort.nix` directly via
`lib.runTests`: exact `.rsc` text for each kind's happy path (including
derived `!k` rendering and `before`/`after` ordering between whole paths),
and that documented error cases actually throw (duplicate `find`/derived
identity within one path's `items`, missing `find` on `kind = "effect"`,
and a dependency cycle). Tests are grouped by topic into one file per
sibling; `lib/tests/default.nix` holds shared test helpers, auto-discovers
and merges every sibling file's tests via `builtins.readDir`, and runs them
through `lib.runTests` — adding a new file to the directory is enough to
have its tests picked up, nothing else to wire up.
`checks/render-unit-tests.nix` forces evaluation of `lib/tests/` and fails
the build with the failing tests' names and expected-vs-actual values,
exposed as `checks.<system>.render-unit-tests`.

`modules/tests/` exercises `modules/*.nix` directly, one file per module,
auto-discovered and run the same way. Unlike `lib/tests/`, these assert on
the compiled `routeros.config` attrset returned by `evalConfig` rather than
on rendered `.rsc` text — what a module's options compile down to,
decoupled from how `lib/render_rsc.nix` renders that attrset, which
`lib/tests/` already covers on its own. `checks/module-unit-tests.nix`
mirrors `checks/render-unit-tests.nix` for `modules/tests/`, exposed as
`checks.<system>.module-unit-tests`.
