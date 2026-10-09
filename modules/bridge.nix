{
  lib,
  config,
  ...
}: let
  inherit (lib) mkOption mkIf types mapAttrsToList concatMap removeAttrs;

  cfg = config.bridge;

  # RouterOS field value: bool, int, or string.
  itemValueType = types.oneOf [
    types.bool
    types.int
    types.str
  ];

  # A port's fields are freehand RouterOS fields; its interface name is
  # the attr key, not a field of its own.
  portSubmodule = {
    freeformType = types.attrsOf itemValueType;
  };

  bridgeSubmodule = {name, ...}: {
    options = {
      name = mkOption {
        type = types.str;
        default = name;
        description = ''
          The bridge interface's name on the device.
        '';
      };

      ports = mkOption {
        type = types.attrsOf (types.submodule portSubmodule);
        default = {};
        description = ''
          Interfaces added to this bridge, keyed by interface name.
          Values are the port's RouterOS fields (e.g. `priority`).
        '';
      };
    };

    freeformType = types.attrsOf itemValueType;
  };

  # One item per bridge: the bridge's name plus its freehand fields,
  # minus `ports` (those become the port path's items).
  bridgeItems =
    mapAttrsToList
    (name: bridge: {name = name;} // removeAttrs bridge ["ports"])
    cfg.bridges;

  # One item per bridge port, carrying the bridge and interface it
  # belongs to alongside the port's own fields.
  portItems =
    concatMap
    (name: let
      bridge = cfg.bridges.${name};
    in
      mapAttrsToList
      (interface: port:
        {
          bridge = name;
          interface = interface;
        }
        // port)
      bridge.ports)
    (builtins.attrNames cfg.bridges);
in {
  options.bridge.enable = mkOption {
    type = types.bool;
    default = false;
    description = ''
      Whether routnix manages the bridge interfaces (`/interface
      bridge`) and their ports (`/interface bridge port`) from
      `bridge.bridges`. While disabled, `bridge.bridges` has no effect
      and neither path is touched.
    '';
  };

  options.bridge.bridges = mkOption {
    type = types.attrsOf (types.submodule bridgeSubmodule);
    default = {};
    description = ''
      Bridges to configure, keyed by bridge interface name. A bridge's
      own RouterOS fields (e.g. `mtu`) sit directly on its submodule.
    '';
  };

  config = mkIf cfg.enable {
    routeros.config."/interface bridge" = {
      kind = "keyed";
      key = item: {inherit (item) name;};
      items = bridgeItems;
    };

    routeros.config."/interface bridge port" = {
      kind = "keyed";
      after = ["/interface bridge"];
      key = item: {inherit (item) interface;};
      # Removes ports whose `bridge` no longer names an existing bridge -- the
      # state a port is left in when its bridge is replaced -- so the items
      # below re-add the declared ones.
      preScript = ''
        :foreach p in=[/interface bridge port find] do={
          :local b [/interface bridge port get $p bridge]
          :if ([:len [/interface bridge find where name=$b]] = 0) do={
            /interface bridge port remove $p
          }
        }
      '';
      # Ports RouterOS creates on its own are dynamic and can't be managed here.
      ignore = [{dynamic = true;}];
      items = portItems;
    };
  };
}
