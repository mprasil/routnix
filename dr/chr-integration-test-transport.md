# Context

The integration check needs to exercise real RouterOS behavior against an
actual RouterOS instance, but RouterOS knows nothing about NixOS-specific
VM tooling.

# Decision

`checks/routeros_machine.py` wraps nixpkgs' `QemuMachine` for QEMU
lifecycle and serial-output capture only — the NixOS backdoor shell is
never used, since RouterOS knows nothing about it — and adds SSH/SCP
helpers. Its `QemuStartCommand` subclass omits virtio-serial/virtconsole so
RouterOS keeps COM1 as its console. Commands run as the default `admin`
account with its empty password; no setup step on the guest is needed.
