# The `bridge` module, with the bridge's `mtu` and a port's `pvid`
# changed from bridge_basic.nix. Same field sets, different values, so
# each entry converges via `set` in place rather than a re-add.
# routeros_test.py's "bridge_edit_in_place" subtest applies this after
# bridge_basic.nix.
{
  bridge.enable = true;
  bridge.bridges.routnix-test-bridge = {
    mtu = 1300;
    ports = {
      routnix-test-vlan = {pvid = 20;};
      routnix-test-vlan2 = {};
    };
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
