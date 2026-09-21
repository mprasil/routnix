# Context

`routeros.config."/path".<block>` is a generic, low-level escape hatch that
maps closely to RouterOS's own path/field structure. Most users would want
typed, curated options instead of writing raw RouterOS paths and fields
directly.

# Options considered

## Low-level DSL only

Keep `routeros.config` as the only interface; users always write RouterOS
paths and fields directly, however low-level that is for common cases.

## Typed modules compiling down to the low-level DSL

Curated modules (e.g. `deviceConfig.firewall.sshAccess`) compile down into
`routeros.config` under the hood — the same relationship as
`systemd.services.<name>` compiling down into `systemd.units.<name>.text`
in NixOS, or `virtualisation.oci-containers.containers.<name>` compiling
down to a `docker`/`podman`-specific implementation depending on
`virtualisation.oci-containers.backend`. The low-level DSL remains as the
generic escape hatch underneath. Not started; no typed modules exist yet,
and no subsystem has been chosen to prototype first. Given the current
RouterOS-only scope (see
[`../dr/routeros-namespace-scope.md`](../dr/routeros-namespace-scope.md)),
there's no `backend`-style selector to build yet either — that would only
become relevant if/when a second backend is ever pursued, which isn't
planned.
