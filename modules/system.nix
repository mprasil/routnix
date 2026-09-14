{lib, ...}: let
  inherit (lib) mkOption types;
in {
  options.device.platform = mkOption {
    type = types.enum ["routeros_v6" "routeros_v7"];
    default = "routeros_v7";
    description = ''
      Type of platform that the device is using. This drives how and which
      configuration is generated.
    '';
  };
}
