{
  routeros.config."/ip firewall address-list" = {
    kind = "unordered";
    after = ["/ip firewall filter"];
    find = item: {address = item.address;};
    items = [
      {
        address = "10.0.0.1";
        list = "foo";
      }
    ];
  };

  routeros.config."/ip firewall filter" = {
    kind = "ordered";
    after = ["/ip firewall address-list"];
    find = item: {comment = item.comment;};
    items = [
      {
        chain = "input";
        action = "accept";
        comment = "allow-input";
      }
    ];
  };
}
