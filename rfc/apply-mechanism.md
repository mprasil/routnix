# Context

routnix renders `.rsc` text but has no implemented way to get it onto a
router and applied.

# Options considered

## Direct scp + /import, no rollback

Copy the rendered `.rsc` to the router and run `/import`, exactly as the
integration check already does non-interactively against a CHR VM (see
[`../dr/chr-integration-test-transport.md`](../dr/chr-integration-test-transport.md))
— a working reference for the transport, not an apply implementation. A
failure partway through `/import` leaves a half-applied config with no
rollback. This is what the `apply` wrapper (see
[`../dr/multi-router-flake-shape.md`](../dr/multi-router-flake-shape.md))
implements today, as a starting point rather than a final choice between
this option and safe-mode.

## scp + /import wrapped in RouterOS's safe-mode

Wrap the same transport in RouterOS's `/safe-mode take` / `release` so a
failure rolls back rather than leaving a half-applied config.

Open questions not yet discussed in depth regardless of which option is
chosen: dry-run/plan support, and behavior on connection failure mid-apply.
