# The `bridge` module, with the bridge's `mtu` and a port's `pvid`
# dropped from bridge_edit.nix. A changed field set is reconciled by
# replacing the entry, so each dropped field returns to its default.
# routeros_test.py's "bridge_drop_param" subtest applies this after
# bridge_edit.nix.
{
  bridge.enable = true;
  bridge.bridges.routnix-test-bridge = {
    ports = {
      routnix-test-vlan = {};
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
