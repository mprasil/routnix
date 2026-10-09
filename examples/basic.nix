{
  routeros.config."/ip firewall address-list" = {
    kind = "unordered";
    ignore = [
      {
        comment = "nomanage";
      }
    ];
    items = [
      {
        address = "192.168.1.0/24";
        list = "trusted-ips";
      }
    ];
  };

  routeros.config."/ip firewall filter" = {
    kind = "ordered";
    after = ["/ip firewall address-list"];
    items = [
      {
        chain = "input";
        action = "accept";
        protocol = "icmp";
        comment = "allow-icmp";
      }
      {
        chain = "input";
        action = "accept";
        "connection-state" = "established,related";
        comment = "allow-established";
      }
      {
        chain = "input";
        action = "accept";
        "src-address-list" = "trusted-ips";
        comment = "allow-trusted";
      }
      {
        chain = "input";
        action = "accept";
        protocol = "tcp";
        "dst-port" = 22;
        comment = "allow-ssh";
      }
      {
        chain = "input";
        action = "drop";
        comment = "drop-rest";
      }
    ];
  };

  # Bridge interfaces (/interface bridge) and their ports
  # (/interface bridge port), keyed by interface name:
  #
  #   bridge.bridges.home-lan.ports.ether2 = { };
  bridge.enable = true;
  bridge.bridges.home-lan.mtu = 1500;
}
