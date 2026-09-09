{
  lib,
  pkgs,
  ...
}: let
  versions = import ./ros_versions.nix;
in
  lib.mapAttrs (alias: params:
    pkgs.fetchzip {
      name = "routeros-image-chr-v${params.version}";
      url = "https://download.mikrotik.com/routeros/${params.version}/chr-${params.version}.img.zip";
      hash = params.hash;
      stripRoot = false;
    })
  versions
