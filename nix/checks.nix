{
  lib,
  pkgs,
  routnixLib,
}: let
  images = import ../images.nix {inherit lib pkgs;};
in
  {
    # Pure-Nix unit tests for lib/render_rsc.nix and lib/toposort.nix
    # (lib/tests/): throws (failing the build) if any test in
    # lib/tests/ fails.
    render-unit-tests = pkgs.callPackage ../checks/render-unit-tests.nix {};

    # Pure-Nix unit tests for modules/*.nix (modules/tests/): throws
    # (failing the build) if any test in modules/tests/ fails.
    module-unit-tests = pkgs.callPackage ../checks/module-unit-tests.nix {};
  }
  // (lib.mapAttrs' (
      alias: image:
        lib.nameValuePair "routeros-${alias}" (pkgs.callPackage ../checks/routeros.nix {
          inherit routnixLib image;
          name = alias;
        })
    )
    images)
