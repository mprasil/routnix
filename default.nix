# Entry point exposing routnix's library and the packages and checks it can
# build for a given `pkgs`:
#
#   let
#     pkgs = import <nixpkgs> {};
#     routnix = import (fetchTarball "https://github.com/mprasil/routnix/archive/<rev>.tar.gz") {inherit pkgs;};
#   in
#     routnix.lib.mkDeviceConfig {inherit pkgs; name = "home-router"; modules = [./home-router.nix];}
#
# `pkgs` defaults to `<nixpkgs>`; pass it explicitly to pin a specific
# nixpkgs.
{
  pkgs ? import <nixpkgs> {},
  lib ? pkgs.lib,
}: let
  routnixLib = import ./lib {inherit lib;};
in {
  lib = routnixLib;
  packages = import ./nix/packages.nix {inherit lib pkgs routnixLib;};
  checks = import ./nix/checks.nix {inherit lib pkgs routnixLib;};
}
