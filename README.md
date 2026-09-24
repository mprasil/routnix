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
      { chain = "input"; action = "accept"; "src-address-list" = "trusted-ips"; }
      { chain = "input"; action = "accept"; protocol = "tcp"; "dst-port" = 22; }
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

`apply` is a thin wrapper around plain `scp`/`ssh`: no rollback yet if
`/import` fails partway through, and no credentials are baked into the
package. Auth, host keys, and identity are entirely up to your own
`ssh`/`scp` config and agent, the same as `ssh admin@router` would use
directly. The target `user@host` is normally passed at invocation time;
passing `host` to `mkDeviceConfig` instead bakes in a default, so a bare
`nix run .#home-router.apply` works. Extra options for cases not already
covered by `~/.ssh/config` (e.g. a non-default port or identity file) can
be baked in via the `sshOptions`/`scpOptions` lists, or passed
per-invocation via the `ROUTNIX_SSH_OPTS`/`ROUTNIX_SCP_OPTS`
space-separated env vars (applied after the baked-in ones):

```nix
home-router = routnix.lib.mkDeviceConfig {
  inherit pkgs;
  name = "home-router";
  modules = [./routers/home-router.nix];
  host = "admin@192.168.88.1";
  sshOptions = ["-p" "2222"];
  scpOptions = ["-P" "2222"];
};
```

```console
$ nix run .#home-router.apply                    # uses the host default
$ nix run .#home-router.apply -- admin@10.0.0.1  # override at runtime
$ ROUTNIX_SSH_OPTS="-p 2222" ROUTNIX_SCP_OPTS="-P 2222" nix run .#home-router.apply
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

## Running a device's config in a VM

Every device also gets its own runnable VM, which boots a CHR image and
applies that device's rendered `.rsc` to it once RouterOS is up:

```nix
home-router = routnix.lib.mkDeviceConfig {
  inherit pkgs;
  name = "home-router";
  modules = [./routers/home-router.nix];
  vm = {rosVersion = "stable-v7"; sshPort = 2222;};
};
```

```console
$ nix run .#home-router.vm
```

It prints the ssh command to use (`ssh -p 2222 admin@127.0.0.1`) and stays
in the foreground until the VM is stopped; Ctrl-C stops it. The guest
console is logged to a file whose path is printed, so pass `--console` to
attach it to the terminal instead (the VM is then stopped with `ctrl-A x`).

`vm` defaults to `rosVersion = "stable-v7"`, `sshPort = 2222`, and
`console = false`, so a bare `nix run .#home-router.vm` works; the port can
also be set with `VM_SSH_PORT`. `vm.image` takes any CHR image directory
(e.g. `.#ros-image-<alias>`) in place of `rosVersion`. `rosVersion` has to
match the device's `device.platform`, since the `.rsc` is rendered for that
platform; a mismatch is an error, while `vm.image` skips the check.

The VM's disk is a QEMU snapshot, so nothing applied to it survives.

## Status

RouterOS-only, no plans otherwise (see
[`dr/routeros-namespace-scope.md`](./dr/routeros-namespace-scope.md) for the
naming rationale), though not necessarily ruled out in the future.

## Inspirations

- [`mikrotik.nix`](https://github.com/nrabulinski/mikrotik.nix) — declarative
  RouterOS configuration via a Nix module system, rendering of rsc script is
  done in Rust code rather than pure nix.
