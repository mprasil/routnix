{
  description = "routnix - declarative RouterOS configuration via Nix";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
    ...
  }: let
    forAllSystems = nixpkgs.lib.genAttrs [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    lib = nixpkgs.lib;
    routnixLib = import ./lib {inherit lib;};
  in {
    lib = routnixLib;

    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      example = routnixLib.evalConfig {modules = [./examples/basic.nix];};
      cycleExample = routnixLib.evalConfig {modules = [./examples/cycle.nix];};
    in {
      example = pkgs.writeText "routnix-example.rsc" example.rsc;
      # Intentionally cyclic `after`/`after` between the two entries;
      # only exists to exercise the cycle-detection error path.
      cycle-example = pkgs.writeText "routnix-cycle-example.rsc" cycleExample.rsc;
      ros-vm-images = import ./images.nix {inherit lib pkgs;};
      ros-vms = import ./vms.nix {inherit lib pkgs;};
    });

    checks = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in
      {
        # Pure-Nix unit tests for lib/render_rsc.nix and lib/toposort.nix
        # (lib/tests.nix): throws (failing the build) if any test in
        # lib/tests.nix fails.
        render-unit-tests = pkgs.callPackage ./checks/render-unit-tests.nix {};
      }
      // (lib.mapAttrs' (
          alias: image:
            lib.nameValuePair "routeros-${alias}" (pkgs.callPackage ./checks/routeros.nix {
              inherit routnixLib image;
              name = alias;
            })
        )
        self.packages.${system}.ros-vm-images));
  };
}
