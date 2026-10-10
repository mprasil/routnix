{
  rsc,
  throws,
  ...
}: {
  # -- kind = "inventory" ----------------------------------------------

  # Each item is located by `find` and `configure`'s commands run
  # against the resolved entry (here a plain `set`).
  testInventoryConfiguresExistingEntry = {
    expr = rsc {
      routeros.config."/interface ethernet" = {
        kind = "inventory";
        find = item: {"default-name" = item.defaultName;};
        configure = item: "set $item name=" + item.name;
        items = [{defaultName = "ether1"; name = "lan1";}];
      };
    };
    expected = ''
      /interface ethernet
      {
        :local item [/interface ethernet find where default-name="ether1"]
        :if ($item = "") do={
          :put "routnix: no entry matching find in /interface ethernet"
          :error "routnix-no-entry-matching-find"
        }
        :if ([:len $item] > 1) do={
          :put "routnix: find matched more than one entry in /interface ethernet"
          :error "routnix-find-matched-multiple-entries"
        }
        set $item name=lan1
      }
    '';
  };

  # `configure` can run commands other than `set` (here enable/disable),
  # and each item is rendered in its own scoped block.
  testInventoryArbitraryConfigurePerItem = {
    expr = rsc {
      routeros.config."/system package" = {
        kind = "inventory";
        find = item: {name = item.name;};
        configure = item: if item.enable then "enable $item" else "disable $item";
        items = [
          {name = "ipv6"; enable = true;}
          {name = "mpls"; enable = false;}
        ];
      };
    };
    expected = ''
      /system package
      {
        :local item [/system package find where name="ipv6"]
        :if ($item = "") do={
          :put "routnix: no entry matching find in /system package"
          :error "routnix-no-entry-matching-find"
        }
        :if ([:len $item] > 1) do={
          :put "routnix: find matched more than one entry in /system package"
          :error "routnix-find-matched-multiple-entries"
        }
        enable $item
      }
      {
        :local item [/system package find where name="mpls"]
        :if ($item = "") do={
          :put "routnix: no entry matching find in /system package"
          :error "routnix-no-entry-matching-find"
        }
        :if ([:len $item] > 1) do={
          :put "routnix: find matched more than one entry in /system package"
          :error "routnix-find-matched-multiple-entries"
        }
        disable $item
      }
    '';
  };

  # Nothing is ever added or removed, so an empty `items` list renders
  # nothing at all (not even a prune sweep).
  testInventoryEmptyItemsRendersNothing = {
    expr = rsc {
      routeros.config."/x" = {
        kind = "inventory";
        find = item: {a = item.a;};
        configure = item: "set $item name=x";
        items = [];
      };
    };
    expected = "\n";
  };

  testInventoryMissingFindThrows = {
    expr = throws (rsc {
      routeros.config."/x" = {
        kind = "inventory";
        configure = item: "set $item name=x";
        items = [{a = "1";}];
      };
    });
    expected = true;
  };

  testInventoryMissingConfigureThrows = {
    expr = throws (rsc {
      routeros.config."/x" = {
        kind = "inventory";
        find = item: {a = item.a;};
        items = [{a = "1";}];
      };
    });
    expected = true;
  };

  testInventoryDuplicateFindThrows = {
    expr = throws (rsc {
      routeros.config."/x" = {
        kind = "inventory";
        find = item: {a = item.a;};
        configure = item: "set $item name=x";
        items = [{a = "1";} {a = "1";}];
      };
    });
    expected = true;
  };
}