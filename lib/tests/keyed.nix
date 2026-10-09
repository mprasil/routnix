{
  rsc,
  throws,
  lib,
  renderArgs,
  ...
}: let
  # Same tag formula as lib/render_rsc/keyed.nix, so the expected text
  # stays in step with the renderer.
  tagged = item: let
    item' = item // {comment = item.comment or "";};
    shape = lib.substring 0 8 (builtins.hashString "md5" (lib.concatStringsSep "," (builtins.attrNames item')));
    value = lib.substring 0 8 (builtins.hashString "md5" (renderArgs item'));
    tag = "routnix:${shape}:${value}";
    tagText = tag + (if item'.comment == "" then "" else " " + item'.comment);
  in {
    inherit shape value tag;
    rendered = renderArgs (item' // {comment = tagText;});
  };
in {
  # -- kind = "keyed" ---------------------------------------------------

  # Pruning is mandatory regardless of how many items are declared, so
  # an empty `items` list must still emit the prune sweep (and thus
  # remove anything left over at the path) rather than rendering
  # nothing at all for it.
  testKeyedEmptyItemsStillPrunes = {
    expr = rsc {
      routeros.config."/x" = {
        kind = "keyed";
        key = item: {b = item.b;};
        items = [];
      };
    };
    expected = ''
      /x
      :local ignore ({})
      :local managed ({})
      :foreach i in=[/x find] do={
        :if ([:find ($managed,$ignore) $i -1] < 0) do={ /x remove $i }
      }
    '';
  };

  # One item's block carries all four reconciliation branches: the tag
  # is written on `add`, the stored tag is compared for the in-sync
  # (`set managed`), same-shape `set`, and replace cases. A user
  # comment is appended after the tag.
  testKeyedReconcilesItemWithTag = let
    i = tagged {name = "home-lan"; mtu = 1500; comment = "uplink";};
  in {
    expr = rsc {
      routeros.config."/x" = {
        kind = "keyed";
        key = item: {name = item.name;};
        items = [{name = "home-lan"; mtu = 1500; comment = "uplink";}];
      };
    };
    expected = ''
      /x
      :local ignore ({})
      :local managed ({})
      {
        :local match [/x find where name="home-lan"]
        :if ([:len $match] > 1) do={
          :error ("routnix: key matched more than one entry in /x")
        }
        :if ([:len $match] = 1 && [:find $ignore ($match->0) -1] >= 0) do={
          :error ("routnix: /x: declared key is occupied by an ignored entry")
        }
        :if ([:len $match] = 0) do={
          :set managed ($managed, [add ${i.rendered}])
        } else={
          :local item ($match->0)
          :local cur [get $item comment]
          :if ($cur ~ "^routnix:${i.shape}:${i.value}") do={
            :set managed ($managed, $match)
          } else={
            :if ($cur ~ "^routnix:${i.shape}:") do={
              set $item ${i.rendered}
              :set managed ($managed, $match)
            } else={
              remove $item
              :set managed ($managed, [add ${i.rendered}])
            }
          }
        }
      }
      :foreach i in=[/x find] do={
        :if ([:find ($managed,$ignore) $i -1] < 0) do={ /x remove $i }
      }
    '';
  };

  # `ignore` predicates resolve to ids before any item is reconciled, so
  # a declared key already occupied by an ignored entry is caught by the
  # guard rather than reconciled against it.
  testKeyedIgnoreResolvedBeforeItems = let
    i = tagged {interface = "ether1";};
  in {
    expr = rsc {
      routeros.config."/x" = {
        kind = "keyed";
        key = item: {interface = item.interface;};
        ignore = [{dynamic = true;}];
        items = [{interface = "ether1";}];
      };
    };
    expected = ''
      /x
      :local ignore ({})
      :set ignore ($ignore, [/x find where dynamic=yes])
      :local managed ({})
      {
        :local match [/x find where interface="ether1"]
        :if ([:len $match] > 1) do={
          :error ("routnix: key matched more than one entry in /x")
        }
        :if ([:len $match] = 1 && [:find $ignore ($match->0) -1] >= 0) do={
          :error ("routnix: /x: declared key is occupied by an ignored entry")
        }
        :if ([:len $match] = 0) do={
          :set managed ($managed, [add ${i.rendered}])
        } else={
          :local item ($match->0)
          :local cur [get $item comment]
          :if ($cur ~ "^routnix:${i.shape}:${i.value}") do={
            :set managed ($managed, $match)
          } else={
            :if ($cur ~ "^routnix:${i.shape}:") do={
              set $item ${i.rendered}
              :set managed ($managed, $match)
            } else={
              remove $item
              :set managed ($managed, [add ${i.rendered}])
            }
          }
        }
      }
      :foreach i in=[/x find] do={
        :if ([:find ($managed,$ignore) $i -1] < 0) do={ /x remove $i }
      }
    '';
  };

  # Two items with the same `key` would collapse into one entry, so the
  # duplicate-identity check uses `key`, not the items' other fields.
  testKeyedDuplicateKeyThrows = {
    expr = throws (rsc {
      routeros.config."/x" = {
        kind = "keyed";
        key = item: {interface = item.interface;};
        items = [
          {interface = "ether1"; bridge = "a";}
          {interface = "ether1"; bridge = "b";}
        ];
      };
    });
    expected = true;
  };

  testKeyedMissingKeyThrows = {
    expr = throws (rsc {
      routeros.config."/x" = {
        kind = "keyed";
        items = [{name = "home-lan";}];
      };
    });
    expected = true;
  };
}
