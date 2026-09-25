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
    # export routnix library
    lib = routnixLib;

    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      images = import ./images.nix {inherit lib pkgs;};
      vms = import ./vms.nix {inherit lib pkgs;};

      example = routnixLib.mkDeviceConfig {
        inherit pkgs;
        name = "example";
        modules = [./examples/basic.nix];
      };
      # VM image for specific ROS version
      ros-vm-images = lib.mapAttrs' (name: value: lib.nameValuePair "ros-image-${name}" value) images;
      # VM with specific ROS version
      ros-vms = lib.mapAttrs' (name: value: lib.nameValuePair "ros-vm-${name}" value) vms;

      # Docs
      eval = routnixLib.evalConfig {modules = [];};
      docs = pkgs.nixosOptionsDoc {
        inherit (eval) options;
        transformOptions = opt:
          opt
          # nixpkgs declares `_module.args` visible at the root of the option
          # tree (lib/modules.nix); it isn't part of routnix's API.
          // lib.optionalAttrs (lib.head opt.loc == "_module") {visible = false;}
          // {
            # Declarations are the absolute store paths the modules were loaded
            # from; report them relative to the flake source instead.
            declarations = map (decl: {name = lib.removePrefix "${self.outPath}/" (toString decl);}) opt.declarations;
          };
      };
      documentation = pkgs.runCommand "routnix docs" {} ''
        cp ${docs.optionsAsciiDoc} routnix.adoc
        ${pkgs.asciidoctor}/bin/asciidoctor  -D $out routnix.adoc
      '';
    in
      {
        inherit example documentation;
      }
      // ros-vm-images
      // ros-vms);

    checks = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      images = import ./images.nix {inherit lib pkgs;};
    in
      {
        # Pure-Nix unit tests for lib/render_rsc.nix and lib/toposort.nix
        # (lib/tests/): throws (failing the build) if any test in
        # lib/tests/ fails.
        render-unit-tests = pkgs.callPackage ./checks/render-unit-tests.nix {};

        # Pure-Nix unit tests for modules/*.nix (modules/tests/): throws
        # (failing the build) if any test in modules/tests/ fails.
        module-unit-tests = pkgs.callPackage ./checks/module-unit-tests.nix {};
      }
      // (lib.mapAttrs' (
          alias: image:
            lib.nameValuePair "routeros-${alias}" (pkgs.callPackage ./checks/routeros.nix {
              inherit routnixLib image;
              name = alias;
            })
        )
        images));
  };
}
