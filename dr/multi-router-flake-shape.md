# Context

`evalConfig { modules }` is the per-router unit of evaluation (see
[`evalconfig-per-router-unit.md`](./evalconfig-per-router-unit.md));
routnix needs a flake output shape and command surface for declaring
several routers and applying any single one with a simple command.

# Options considered

- Library only: users wire their own flake outputs and write their own
  apply script.
- A conventional flake attribute naming each router plus a
  routnix-provided CLI (a `nixos-rebuild`-style binary) that reads it.
- Per-router pass-through packages: a helper that returns the rendered
  `.rsc` as a package with an apply wrapper attached via `passthru`.

# Decision

`lib.mkDeviceConfig { pkgs, modules, name ? "routnix", host ? null,
openssh ? pkgs.openssh, sshOptions ? [], scpOptions ? [] }` evaluates
`modules` via `evalConfig`, renders the `.rsc` as a `pkgs.writeText`
package, and attaches a `writeShellApplication` apply wrapper as its
`apply` attribute (`rscPackage // { apply = ...; }`, the same `passthru`
shape `pkgs.foo.passthru.*` uses in nixpkgs). Users declare one
`mkDeviceConfig` call per router as an ordinary flake package:

```nix
packages.<system>.home-router = routnix.lib.mkDeviceConfig {
  inherit pkgs;
  name = "home-router";
  modules = [./routers/home-router.nix];
};
```

```console
$ nix build .#home-router                          # inspect / diff the .rsc
$ nix run   .#home-router.apply -- admin@192.168.88.1
```

The apply wrapper's own transport/rollback behavior is a separate, still
open question (see
[`../rfc/apply-mechanism.md`](../rfc/apply-mechanism.md)). Its target
host is a runtime argument to `apply`, with an optional default passed to
`mkDeviceConfig` as `host` so a bare `nix run .#router.apply` works;
runtime arguments still override the default, and a default address is
baked into the store when one is set. Like `sshOptions`/`scpOptions`,
this is user-side apply configuration rather than part of the device's
routnix configuration (there is no `routeros.*` option for it). The
wrapper's own auth and identity come entirely from the ambient
`ssh`/`scp` config and agent, matching `nixos-rebuild --target-host` and
how the integration check already talks to RouterOS (see
[`chr-integration-test-transport.md`](./chr-integration-test-transport.md)).

`mkDeviceConfig` takes `pkgs` explicitly (rather than being curried over
it) since `routnix.lib` itself stays a plain, system-agnostic attrset —
`mkDeviceConfig` is the one function in it that needs a concrete `pkgs` to
build derivations. The name doesn't commit to `.rsc` specifically, leaving
room for other rendered outputs per device later without renaming it
again.

There's no flake-level notion of "all routers" and no routnix-provided
CLI; each router is just a package a user's own flake declares and builds
like any other.
