{
  routeros.config."/ip/firewall/address-list".items = [
    {
      address = "192.168.1.0/24";
      list = "trusted-ips";
    }
  ];

  routeros.config."/ip/firewall/filter" = {
    after = [ "/ip/firewall/address-list" ];
    items = [
      {
        chain = "input";
        action = "accept";
        protocol = "icmp";
      }
      {
        chain = "input";
        action = "accept";
        "connection-state" = "established,related";
      }
      {
        chain = "input";
        action = "accept";
        protocol = "tcp";
        "dst-port" = 22;
        "src-address-list" = "trusted-ips";
      }
      {
        chain = "input";
        action = "drop";
      }
    ];
  };
}
