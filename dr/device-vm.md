# Context

`mkDeviceConfig` renders a device's config and attaches an `apply` wrapper
for putting it on a real router, and routnix separately packages CHR images
and boots them (`nix/vms.nix`, `images.nix`). Nothing connected a user's own
device config to a VM, so trying a config out meant a physical router, or
hand-driving QEMU and `scp`/`/import` the way the integration check does.

# Options considered

- A `vm` attribute on the package `mkDeviceConfig` returns, alongside
  `apply`.
- A separate `lib.mkVm` function taking an already-built device.
- An optional config argument on the existing `.#ros-vm-*` scripts.

# Decision

The `vm` attribute. It gives a device's VM the same command surface as its
`apply` (`nix run .#home-router.vm`) and keeps `mkDeviceConfig` the one
place a router is declared; `lib.mkVm` would have split that story across
two functions, and the `.#ros-vm-*` scripts are per RouterOS version rather
than per device, so a config there could only ever be a runtime argument.

`vm` is optional and defaults to `{}`, merged over `rosVersion =
"stable-v7"`, `image = null`, `sshPort = 2222`, `console = false`, so
`nix run .#<device>.vm` works without declaring anything:

```nix
home-router = routnix.lib.mkDeviceConfig {
  inherit pkgs;
  name = "home-router";
  modules = [./routers/home-router.nix];
  vm = {rosVersion = "long-term-v6"; sshPort = 2222;};
};
```

`rosVersion` names an entry in `ros_versions.nix`, resolved through
`images.nix`; `vm.image` takes any CHR image directory instead (e.g.
`.#ros-image-<alias>`) and wins if both are set. Because the rendered `.rsc`
follows `device.platform`, a `rosVersion` whose RouterOS major doesn't match
the device's platform throws rather than booting a VM the config wasn't
rendered for; `vm.image` skips that check, since the image's version isn't
known. This is the only place `lib/` reaches outside rendering, and only
into routnix's own `ros_versions.nix`/`images.nix`.

The runner (`lib/mk_vm.nix`) boots the image with a snapshot disk and a
loopback-only `hostfwd` to `sshPort`, waits for RouterOS SSH by polling
`/system identity print` (RouterOS opens port 22 before its sshd can
complete the banner exchange, so a TCP connect isn't enough), `scp`s the
same `.rsc` `apply` would send, `/import`s it, and prints the ssh command.
Its transport is the integration check's, not `apply`'s — `-F none -o
StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o
PubkeyAuthentication=no -o BatchMode=yes` against `admin@127.0.0.1` — since
a fresh VM has an unknown host key, no key-based auth, and an empty admin
password that RouterOS accepts through the "none" auth method. It warns
rather than fails if the VM stops answering over SSH after the import, e.g.
because the config declared a `/user` change or a firewall that drops 22.
`VM_SSH_PORT` overrides `sshPort` at runtime.

The guest console is attached only with `--console` (or `vm.console =
true`); otherwise serial output goes to a file whose path is printed, which
is what leaves the terminal free for Ctrl-C to stop the VM. Attaching the
console means QEMU owns the terminal, so Ctrl-C reaches the guest instead
and the VM is stopped with the monitor escape `ctrl-A x`.
