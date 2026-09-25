{
  description = "routnix - declarative RouterOS configuration via Nix";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {
    nixpkgs,
    ...
  }: let
    lib = nixpkgs.lib;
    forAllSystems = lib.genAttrs [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    perSystem = forAllSystems (system:
      import ./default.nix {
        inherit lib;
        pkgs = nixpkgs.legacyPackages.${system};
      });
  in {
    # export routnix library
    lib = import ./lib {inherit lib;};

    packages = lib.mapAttrs (_: v: v.packages) perSystem;
    checks = lib.mapAttrs (_: v: v.checks) perSystem;
  };
}
