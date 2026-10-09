# The `bridge` module: a bridge and its ports compile down to
# kind = "keyed" paths (/interface bridge, /interface bridge port).
# ether1 is the interface routeros_test.py itself connects over SSH as,
# so it is never put into the bridge; VLAN interfaces on it stand in
# for physical ports instead. routeros_test.py's "bridge_*" subtests
# apply this and the follow-on edits in sequence.
{
  bridge.enable = true;
  bridge.bridges.routnix-test-bridge = {
    mtu = 1400;
    ports = {
      routnix-test-vlan = {pvid = 10;};
      routnix-test-vlan2 = {};
    };
  };

  # The VLAN interfaces the ports refer to. Declared before the port
  # path, which fails to add a port for an interface that doesn't exist
  # yet.
  routeros.config."/interface vlan" = {
    kind = "unordered";
    before = ["/interface bridge port"];
    items = [
      {name = "routnix-test-vlan"; interface = "ether1"; vlan-id = 100;}
      {name = "routnix-test-vlan2"; interface = "ether1"; vlan-id = 101;}
    ];
  };
}
