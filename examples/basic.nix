{
  routeros.config."/ip/firewall/address-list" = {
    kind = "unordered";
    prune = true;
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

  routeros.config."/ip/firewall/filter" = {
    kind = "ordered";
    after = ["/ip/firewall/address-list"];
    find = item: {comment = item.comment;};
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
        protocol = "tcp";
        "dst-port" = 22;
        "src-address-list" = "trusted-ips";
        comment = "allow-ssh-trusted";
      }
      {
        chain = "input";
        action = "drop";
        comment = "drop-rest";
      }
    ];
  };
}
