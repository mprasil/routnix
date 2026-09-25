# Routnix

Use Nix to declaratively configure network devices. Currently supported are
RouterOS based systems.

> [!NOTE]
> This project is not affiliated with, endorsed by, sponsored by, or otherwise
> associated with Mikrotik - the creator of RouterOS.
>
> Early stage of development, basic functionality is implemented, but expect
> sharp edges and bugs.

## Goals

- Idempotent configuration that's safe to apply repeatedly
- Nix wrapper that takes care of the complicated stuff
- Extensible system of configuration

## How does this work?

You write Nix modules describing the desired state of a router - users, SSH
keys, firewall rules, addresses, and so on - the same way you would describe
a NixOS or home-manager system. Routnix evaluates them and renders the result
as a single RouterOS script (`.rsc`), entirely in Nix:

1. Every module contributes to `routeros.config`, an attrset keyed by
   RouterOS path (e.g. `"/ip firewall filter"`). Each path declares how it is
   managed: an order-sensitive table, a presence-only table, a singleton
   settings object, arbitrary commands, or hardware-bound entries that can
   only be adjusted.
2. Paths that depend on each other are ordered with `before`/`after` and
   topologically sorted, so e.g. an address-list is created before the
   firewall rule that references it.
3. The ordered result is rendered into one `.rsc` script.

The script does not blindly re-add everything on every run. For each declared
item it looks up whether a matching entry already exists, then adds,
repositions, or removes entries until the router matches the declaration, so
importing the same script twice is a no-op rather than a duplicate. At a
managed path, entries that are no longer declared are removed; `ignore`
exempts entries managed by hand or by another tool from that sweep.

`routeros.config` is the low-level escape hatch and maps closely to
RouterOS's own paths and fields. On top of it sit higher-level modules
(`users.*`, `firewall.filter.*`) that compile down to it, the same way NixOS
service modules compile down to units.

## Usage

This project uses module system you know and love from nixpkgs. You provide the
Nix modules to configure your RouterOS devices, Routnix will provide:

- test VM to try the configuration
- modules with higher level abstraction
- deployment automation

This could be your router config:

```nix
{
  # Users and their SSH keys (/user, /user ssh-keys).
  users.enable = true;
  users.users.admin = {
    # null (default) leaves existing keys alone; a list manages them fully.
    sshPubKeys = [
      # Replace with your own public key.
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleExampleExampleExample user@laptop"
    ];
  };

  # Firewall filter rules, grouped into named, orderable blocks.
  firewall.filter.enable = true;
  firewall.filter.rules = {
    established = {
      chain = "input";
      rules = [
        {action = "accept"; "connection-state" = "established,related";}
        {action = "accept"; protocol = "icmp";}
      ];
    };
    ssh = {
      chain = "input";
      after = ["established"];
      rules = [
        {action = "accept"; protocol = "tcp"; "dst-port" = 22;}
      ];
    };
    drop = {
      chain = "input";
      after = ["ssh"];
      rules = [
        {action = "drop";}
      ];
    };
  };
}
```

Anything without a higher-level module yet can be written directly against
`routeros.config`, keyed by RouterOS path:

```nix
{
  routeros.config."/ip firewall address-list" = {
    kind = "unordered";
    items = [
      {address = "192.168.1.0/24"; list = "trusted-ips";}
    ];
  };
}
```

### Flake users


```nix
{
  description = "Router management";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Import Routnix
    routnix = {
      url = "github:mprasil/routnix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    routnix,
    ...
  }: let
    forAllSystems = nixpkgs.lib.genAttrs [
      "x86_64-linux"
      # ..other systems..
    ];
  in {
    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      # Build your router config as package
      home-router = routnix.lib.mkDeviceConfig {
        inherit pkgs;
        name = "home-router";
        modules = [./home-router.nix];
      };
    });
  };
}
```

Then you can:

#### Check the generated `*.rsc` script

```sh
nix build .#home-router && cat result
```

#### Apply the configuration

```sh
nix run .#home-router.apply -- admin@192.168.88.1
```

`apply` copies the rendered `.rsc` to the router over `scp` and runs
`/import` over `ssh`, then removes the file again. Pass `--copy-only` to stop
after the copy. Auth, host keys, and identity are left to your own
`ssh`/`scp` config and agent. Passing `host` to `mkDeviceConfig` bakes in a
default so a bare `nix run .#home-router.apply` works; extra options (e.g. a
non-default port) go in the `sshOptions`/`scpOptions` lists or the
`ROUTNIX_SSH_OPTS`/`ROUTNIX_SCP_OPTS` environment variables. There is no
rollback yet if `/import` fails partway through.

#### Run a test VM with your configuration

```sh
nix run .#home-router.vm
```

This boots a RouterOS CHR image under QEMU/KVM with a snapshot disk and
applies the device's `.rsc` to it over SSH once RouterOS is up, so nothing
touches a real router. `vm.rosVersion` defaults to `stable-v7` and has to
match the device's `device.platform`; `vm.sshPort` (also settable via
`VM_SSH_PORT`) defaults to `2222`. Ctrl-C stops the VM.

### Non-flake users

Without flakes, import the root `default.nix`, which exposes the same
library as the flake's `lib` output:

```nix
let
  pkgs = import <nixpkgs> {};
  # Pin a rev (or use fetchFromGitHub with a hash) for reproducibility.
  routnix = import (fetchTarball "https://github.com/mprasil/routnix/archive/<rev>.tar.gz") {
    inherit pkgs;
  };
in
  routnix.lib.mkDeviceConfig {
    inherit pkgs;
    name = "home-router";
    modules = [./home-router.nix];
  }
```

`pkgs` defaults to `<nixpkgs>`, so `import <src> {}` also works. The
result is an ordinary derivation with `apply` and `vm` attributes, so the
same operations are `nix-build` calls:

```sh
nix-build ./router.nix           # build the .rsc (result is the file)
nix-build ./router.nix -A apply  # build the apply wrapper
./result/bin/apply admin@192.168.88.1
nix-build ./router.nix -A vm     # build the test VM runner
./result/bin/vm-home-router
```

## Learn more

- [`examples/basic.nix`](./examples/basic.nix) - an example config.
- [`checks/configs/`](./checks/configs) - one focused config per feature,
  used by the integration check.
- [`dr/`](./dr) - settled design decisions, one file each.
- [`rfc/`](./rfc) - open design questions, not decided yet.
- `nix build .#documentation` - rendered reference for every option.

## Test drive

You can run VM with [example configuration](./examples/basic.nix) applied right
from this repo with:

```sh
nix run .#example.vm
```

The rendered script on its own is available with `nix build .#example && cat
result`, and a plain CHR VM without any config with `nix run
.#ros-vm-<alias>` (e.g. `.#ros-vm-stable-v7`; see `ros_versions.nix` for the
aliases).


