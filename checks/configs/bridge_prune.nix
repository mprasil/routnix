# The `bridge` module, with the "routnix-test-vlan2" port dropped from
# bridge_drop_param.nix. The port path's mandatory prune sweep removes
# it, while the VLAN interface itself stays declared. routeros_test.py's
# "bridge_prune" subtest applies this after bridge_drop_param.nix.
{
  bridge.enable = true;
  bridge.bridges.routnix-test-bridge = {
    ports.routnix-test-vlan = {};
  };

  routeros.config."/interface vlan" = {
    kind = "unordered";
    before = ["/interface bridge port"];
    items = [
      {name = "routnix-test-vlan"; interface = "ether1"; vlan-id = 100;}
      {name = "routnix-test-vlan2"; interface = "ether1"; vlan-id = 101;}
    ];
  };
}
