# Context

routnix needs a defined unit of evaluation that turns a set of modules into
one router's rendered config.

# Options considered

- A single `evalConfig` call that produces config for multiple routers at
  once.
- `evalConfig { modules }` evaluates one router's modules and returns that
  one router's rendered config.

# Decision

`evalConfig { modules }` evaluates `modules` (plus routnix-provided
modules) via `lib.evalModules`, topologically sorts `config.routeros.config`
(see [`dependency-ordering-toposort.md`](./dependency-ordering-toposort.md)),
and returns the `evalModules` result plus an `rsc` attribute with the
rendered, ordered `.rsc` text — one call per router. Managing several
routers from one flake extends by wrapping multiple calls to this function
(see [`multi-router-flake-shape.md`](./multi-router-flake-shape.md)); no
rework of `evalConfig` itself was needed for that.
