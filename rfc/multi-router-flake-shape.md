# Context

`evalConfig { modules }` is already the right per-router unit of
evaluation (see
[`../dr/evalconfig-per-router-unit.md`](../dr/evalconfig-per-router-unit.md)).
There's no established shape yet for managing several routers from one
flake.

# Options considered

## Wrap multiple evalConfig calls under named attributes

```nix
routnixConfigurations = {
  homeRouter = routnix.lib.evalConfig { modules = [ ./hosts/home-router.nix ]; };
};
```

plus flake plumbing (`packages.<system>."rsc-<name>"`, later
`apps.<system>."activate-<name>"`) once the apply mechanism (see
[`apply-mechanism.md`](./apply-mechanism.md)) exists. No rework of `lib/`
is anticipated; `specialArgs` (a standard `evalModules` feature) is the
expected mechanism if per-router identity ever needs to be threaded into
modules, but this hasn't been needed yet.
