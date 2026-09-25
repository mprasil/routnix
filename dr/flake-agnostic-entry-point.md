# Context

routnix's flake exposes `lib` plus per-system packages/checks, but
non-flake users had no stable import path into the library: reaching it
meant importing the internal `lib/` directory (or a file inside it)
directly, coupling them to routnix's file layout.

# Options considered

- Flakes only: non-flake users import `lib/` themselves and accept the
  coupling to the internal layout.
- A root `default.nix` that re-exports the library, and the packages and
  checks it can build, for a concrete `pkgs`, mirroring the flake's
  outputs.

# Decision

The root `default.nix`:

```nix
{
  pkgs ? import <nixpkgs> {},
  lib ? pkgs.lib,
}: {
  lib = ...;        # same value as the flake's `lib` output
  packages = ...;
  checks = ...;
}
```

Non-flake users pin routnix with `fetchTarball`/`fetchFromGitHub` and
import the result:

```nix
routnix = import (fetchTarball "...") {inherit pkgs;};
routnix.lib.mkDeviceConfig { ... }
```

`pkgs` defaults to `<nixpkgs>` and `lib` to `pkgs.lib`. The flake's
`packages`/`checks` are built by importing this same `default.nix` per
system with the flake's own `pkgs`, so there is one place composing the
outputs. The library in `lib/` stays flake-independent, so this entry
point is a re-export rather than a second implementation.
