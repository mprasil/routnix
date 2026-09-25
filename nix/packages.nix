{
  lib,
  pkgs,
  routnixLib,
}: let
  images = import ../images.nix {inherit lib pkgs;};
  vms = import ./vms.nix {inherit lib pkgs;};

  example = routnixLib.mkDeviceConfig {
    inherit pkgs;
    name = "example";
    modules = [../examples/basic.nix];
  };

  documentation = import ./docs.nix {inherit lib pkgs routnixLib;};

  # CHR image for a specific RouterOS version.
  ros-vm-images = lib.mapAttrs' (name: value: lib.nameValuePair "ros-image-${name}" value) images;
  # Runnable VM with a specific RouterOS version.
  ros-vms = lib.mapAttrs' (name: value: lib.nameValuePair "ros-vm-${name}" value) vms;
in
  {
    inherit example documentation;
  }
  // ros-vm-images
  // ros-vms
