{
  description = "routnix - declarative RouterOS configuration via Nix";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {nixpkgs, ...}: let
    forAllSystems = nixpkgs.lib.genAttrs [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];

    forTestSystems = nixpkgs.lib.genAttrs [
      "x86_64-linux"
    ];

    lib = nixpkgs.lib;
    routnixLib = import ./lib {inherit lib;};
  in {
    lib = routnixLib;

    packages =
      (forAllSystems (
        system: let
          pkgs = nixpkgs.legacyPackages.${system};
          example = routnixLib.evalConfig {modules = [./examples/basic.nix];};
          cycleExample = routnixLib.evalConfig {modules = [./examples/cycle.nix];};
        in {
          example = pkgs.writeText "routnix-example.rsc" example.rsc;
          # Intentionally cyclic `after`/`after` between the two entries;
          # only exists to exercise the cycle-detection error path.
          cycle-example = pkgs.writeText "routnix-cycle-example.rsc" cycleExample.rsc;
        }
      ))
      // (forTestSystems (
        system: let
          pkgs = nixpkgs.legacyPackages.${system};
        in {
          ros-vm-images = import ./images.nix {inherit lib pkgs;};
          ros-vms = import ./vms.nix {inherit lib pkgs;};
        }
      ));

    checks = forTestSystems (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        routeros = pkgs.callPackage ./checks/routeros.nix {inherit routnixLib;};
      }
    );
  };
}
