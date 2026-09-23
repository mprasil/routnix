# routnix

Declarative RouterOS (MikroTik) configuration using the Nix module system,
rendered to idempotent `.rsc` scripts — entirely in Nix, with no external
tool/build step for ordering or rendering.

> [!WARNING]
> Very early and experimental. The low-level DSL shown below works, but
> most of the design (ownership tracking, idempotent updates, high-level
> modules, actually applying config to a router) is still unimplemented or
> unsettled. See [`dr/`](./dr) for settled decisions and [`rfc/`](./rfc)
> for what's still open design space.

## Example

```nix
{
  routeros.config."/ip firewall address-list" = {
    kind = "unordered";
    items = [
      { address = "192.168.1.0/24"; list = "trusted-ips"; }
    ];
  };

  routeros.config."/ip firewall filter" = {
    kind = "ordered";
    after = [ "/ip firewall address-list" ];
    items = [
      { chain = "input"; action = "accept"; protocol = "icmp"; }
      { chain = "input"; action = "accept"; "connection-state" = "established,related"; }
      { chain = "input"; action = "accept"; protocol = "tcp"; "dst-port" = 22; "src-address-list" = "trusted-ips"; }
      { chain = "input"; action = "drop"; }
    ];
  };
}
```

`after`/`before` declare ordering between RouterOS paths (needed since some
config depends on other config existing first, e.g. an address-list before
a firewall rule referencing it); routnix topologically sorts them and
renders a single `.rsc` script in the right order.

## Try it

```console
$ nix build .#example && cat result
```

See `examples/` for the source of that config.

## Using routnix in your own flake

Add routnix as a flake input and call `lib.mkDeviceConfig` once per
router, passing that system's `pkgs` and the router's own modules:

```nix
{
  inputs.routnix.url = "github:<you>/routnix";

  outputs = {self, nixpkgs, routnix}: let
    forAllSystems = nixpkgs.lib.genAttrs ["x86_64-linux"];
  in {
    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      home-router = routnix.lib.mkDeviceConfig {
        inherit pkgs;
        name = "home-router";
        modules = [./routers/home-router.nix];
      };

      office-router = routnix.lib.mkDeviceConfig {
        inherit pkgs;
        name = "office-router";
        modules = [./routers/office-router.nix];
      };
    });
  };
}
```

Each router becomes its own package, with an `apply` wrapper carried
alongside it:

```console
# Build/inspect the rendered .rsc without touching any router
$ nix build .#home-router && cat result

# scp it to the router, `/import` it over ssh, then remove it
$ nix run .#home-router.apply -- admin@192.168.88.1

# Just copy it over, e.g. to review/import by hand
$ nix run .#home-router.apply -- admin@192.168.88.1 --copy-only
```

`apply` is a thin wrapper around plain `scp`/`ssh` — no rollback yet if
`/import` fails partway through, and no host, user, or credentials are
baked into the package: auth, host keys, and identity are entirely up to
your own `ssh`/`scp` config and agent, the same as `ssh admin@router` would
use directly. `ROUTNIX_SSH_OPTS`/`ROUTNIX_SCP_OPTS` pass extra
space-separated options straight through (e.g. a non-default port or
identity file) for cases not already covered by `~/.ssh/config`:

```console
$ ROUTNIX_SSH_OPTS="-p 2222" ROUTNIX_SCP_OPTS="-P 2222" nix run .#home-router.apply -- admin@127.0.0.1
```

## RouterOS CHR VMs

For trying things out against a real RouterOS instance, flake exposes packaged
CHR (Cloud Hosted Router) images and ready-to-run VMs for a set of RouterOS
versions (see `ros_versions.nix`):

```console
$ nix run .#ros-vm-long-term-v7
```

This boots the corresponding CHR image under QEMU/KVM with SSH forwarded
to the host (port `2222` by default, override with `VM_SSH_PORT`). The
underlying disk image is also available on its own via
`.#ros-image-<alias>`, e.g. `.#ros-image-stable-v7`.

To quit the VM, use QEMU monitor escape `ctrl-A x`.

## Status

RouterOS-only, no plans otherwise (see
[`dr/routeros-namespace-scope.md`](./dr/routeros-namespace-scope.md) for the
naming rationale), though not necessarily ruled out in the future.

## Inspirations

- [`mikrotik.nix`](https://github.com/nrabulinski/mikrotik.nix) — declarative
  RouterOS configuration via a Nix module system, rendering of rsc script is
  done in Rust code rather than pure nix.
