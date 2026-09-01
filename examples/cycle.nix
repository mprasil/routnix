{
  routeros.config."/ip/firewall/address-list" = {
    after = [ "/ip/firewall/filter" ];
    items = [
      {
        address = "10.0.0.1";
        list = "foo";
      }
    ];
  };

  routeros.config."/ip/firewall/filter" = {
    after = [ "/ip/firewall/address-list" ];
    items = [
      {
        chain = "input";
        action = "accept";
      }
    ];
  };
}
