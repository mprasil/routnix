# Context

routnix's name and the shape of its top-level options need to fit being
explicitly RouterOS-only for the foreseeable future, without foreclosing a
possible future device-agnostic layer.

# Options considered

- Name the project and its options after RouterOS/MikroTik directly.
- Name the project generically (`routnix`), and nest RouterOS-specific
  options under a `routeros` namespace rather than the top level.

# Decision

The project is named `routnix` ("router" + "nix") rather than something
RouterOS-specific, and `routeros.config` lives nested under a `routeros`
namespace rather than at the top level — the same split modeled by
`virtualisation.oci-containers.backend` vs.
`virtualisation.oci-containers.containers.<name>`. This leaves the top
level free for a possible future device-agnostic layer, without
committing to ever building one; routnix is explicitly RouterOS-only for
now and for the foreseeable future.
