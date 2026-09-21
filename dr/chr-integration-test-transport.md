# Context

The integration check needs to exercise real RouterOS behavior against an
actual RouterOS instance, but RouterOS knows nothing about NixOS-specific
VM tooling.

# Options considered

- Use nixpkgs' `QemuMachine` with the NixOS backdoor shell
  (`.connect()`/`.execute()`) for control.
- Wrap `QemuMachine` for QEMU lifecycle and serial-output capture only,
  adding SSH/SCP helpers instead, and never use the backdoor.

# Decision

`checks/routeros_machine.py` wraps nixpkgs' `QemuMachine` for QEMU
lifecycle and serial-output capture only — the NixOS backdoor shell is
never used, since RouterOS knows nothing about it — and adds SSH/SCP
helpers. Its `QemuStartCommand` subclass omits virtio-serial/virtconsole so
RouterOS keeps COM1 as its console. Commands run as the default `admin`
account with its empty password; no setup step on the guest is needed.
