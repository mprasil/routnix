{
  evalConfig,
  dataFields,
  lib,
  ...
}: let
  # Item comparisons below look at the identifying fields (a bridge's
  # `name`, a port's `bridge`/`interface`) plus the specific param under
  # test, rather than full item equality.
  bridgeItems = entry: entry.items;
  portItems = entry: entry.items;
in {
  testDisabledByDefaultDeclaresNothing = {
    expr = evalConfig {bridge.bridges.home-lan = {};};
    expected = {};
  };

  # Enabling with no bridges still manages both paths (kind = "keyed"
  # prunes unconditionally), so both must be present with empty items.
  testEnabledWithNoBridgesManagesBothPathsEmpty = {
    expr = lib.mapAttrs (_: dataFields) (evalConfig {bridge.enable = true;});
    expected = {
      "/interface bridge" = {
        kind = "keyed";
        items = [];
        ignore = [];
      };
      "/interface bridge port" = {
        kind = "keyed";
        items = [];
        ignore = [{dynamic = true;}];
      };
    };
  };

  testBridgeDeclaredWithFreehandParams = {
    expr = bridgeItems (evalConfig {
      bridge.enable = true;
      bridge.bridges.home-lan = {mtu = 1500;};
    })."/interface bridge";
    expected = [{name = "home-lan"; mtu = 1500;}];
  };

  # `name` defaults to the attr key, so a bridge need not repeat it.
  testBridgeNameDefaultsToAttrKey = {
    expr = map (i: i.name) (bridgeItems (evalConfig {
      bridge.enable = true;
      bridge.bridges.home-lan = {};
    })."/interface bridge");
    expected = ["home-lan"];
  };

  testBridgeNameIsOverridable = {
    expr = map (i: i.name) (bridgeItems (evalConfig {
      bridge.enable = true;
      bridge.bridges.home-lan = {name = "lan-bridge";};
    })."/interface bridge");
    expected = ["lan-bridge"];
  };

  # `ports` is bridge-level config, not a bridge field.
  testPortsNotEmittedOnBridgePath = {
    expr = bridgeItems (evalConfig {
      bridge.enable = true;
      bridge.bridges.home-lan = {
        mtu = 1500;
        ports.ethernet2 = {};
      };
    })."/interface bridge";
    expected = [{name = "home-lan"; mtu = 1500;}];
  };

  testPortDeclaredWithFreehandParams = {
    expr = portItems (evalConfig {
      bridge.enable = true;
      bridge.bridges.home-lan.ports.ethernet2 = {priority = 10;};
    })."/interface bridge port";
    expected = [{bridge = "home-lan"; interface = "ethernet2"; priority = 10;}];
  };

  testPortsFromMultipleBridgesAllEmitted = {
    expr = portItems (evalConfig {
      bridge.enable = true;
      bridge.bridges = {
        home-lan.ports.ethernet2 = {};
        guest.ports.ethernet3 = {};
      };
    })."/interface bridge port";
    expected = [
      {bridge = "guest"; interface = "ethernet3";}
      {bridge = "home-lan"; interface = "ethernet2";}
    ];
  };

  # The emitted `key` functions (functions can't go through `==`, so
  # they're applied to a representative item here).
  testBridgeKeyIsName = {
    expr = (evalConfig {
      bridge.enable = true;
      bridge.bridges.home-lan = {};
    })."/interface bridge".key {
      name = "home-lan";
      mtu = 1500;
    };
    expected = {name = "home-lan";};
  };

  testPortKeyIsInterface = {
    expr = (evalConfig {
      bridge.enable = true;
      bridge.bridges.home-lan.ports.ethernet2 = {};
    })."/interface bridge port".key {
      bridge = "home-lan";
      interface = "ethernet2";
      priority = 10;
    };
    expected = {interface = "ethernet2";};
  };

  # `/interface bridge port` refers to bridges that must exist first.
  testPortPathDependsOnBridgePath = {
    expr = (evalConfig {bridge.enable = true;})."/interface bridge port".after;
    expected = ["/interface bridge"];
  };

  # Replacing a bridge leaves its ports pointing at the removed bridge,
  # so the port path sweeps those dangling ports before the entries
  # re-add the declared ones.
  testPortPathSweepsDanglingPorts = {
    expr = let
      preScript = (evalConfig {bridge.enable = true;})."/interface bridge port".preScript;
    in {
      readsBridge = lib.hasInfix "/interface bridge port get" preScript;
      removesPort = lib.hasInfix "/interface bridge port remove" preScript;
    };
    expected = {
      readsBridge = true;
      removesPort = true;
    };
  };
}
