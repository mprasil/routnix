{
  rsc,
  throws,
  ...
}: {
  # -- kind = "effect" --------------------------------------------------

  # Unlike `"unordered"` (which captures `create`'s own return value as
  # the id directly), `create` for `"effect"` may run arbitrary,
  # non-id-returning commands -- the id is instead resolved by
  # re-running `find` once `create` has run, guarded by an `:error` for
  # the case that still doesn't turn up a match (or turns up more than
  # one).
  testEffectResolvesItemsAndSweeps = {
    expr = rsc {
      routeros.config."/x" = {
        kind = "effect";
        find = item: {a = item.a;};
        create = item: "custom " + item.a;
        items = [{a = "1";}];
      };
    };
    expected = ''
      /x
      :local ignore ({})
      :local managed ({})
      {
        :local item [/x find where a="1"]
        :if ([:len $item] > 1) do={
          :error ("routnix: find matched more than one entry in /x")
        }
        :if ($item = "" || [:find $ignore $item -1] >= 0) do={
          custom 1
          :set item [/x find where a="1"]
          :if ($item = "") do={
            :error ("routnix: create for /x didn't produce an entry matching find")
          }
          :if ([:len $item] > 1) do={
            :error ("routnix: find matched more than one entry in /x")
          }
        }
        :set managed ($managed, $item)
      }
      :foreach i in=[/x find] do={
        :if ([:find ($managed,$ignore) $i -1] < 0) do={ /x remove $i }
      }
    '';
  };

  testEffectIgnoreExemptsMatchedEntriesFromSweep = {
    expr = rsc {
      routeros.config."/x" = {
        kind = "effect";
        ignore = [{c = "keep";}];
        find = item: {a = item.a;};
        create = item: "custom " + item.a;
        items = [{a = "1";}];
      };
    };
    expected = ''
      /x
      :local ignore ({})
      :set ignore ($ignore, [/x find where c="keep"])
      :local managed ({})
      {
        :local item [/x find where a="1"]
        :if ([:len $item] > 1) do={
          :error ("routnix: find matched more than one entry in /x")
        }
        :if ($item = "" || [:find $ignore $item -1] >= 0) do={
          custom 1
          :set item [/x find where a="1"]
          :if ($item = "") do={
            :error ("routnix: create for /x didn't produce an entry matching find")
          }
          :if ([:len $item] > 1) do={
            :error ("routnix: find matched more than one entry in /x")
          }
        }
        :set managed ($managed, $item)
      }
      :foreach i in=[/x find] do={
        :if ([:find ($managed,$ignore) $i -1] < 0) do={ /x remove $i }
      }
    '';
  };

  # Pruning is mandatory regardless of how many items are declared, so
  # an empty `items` list must still emit the prune sweep (and thus
  # remove anything left over at the path) rather than rendering
  # nothing at all for it. `find` is still required for kind =
  # "effect" even though it goes unused here (see
  # testEffectMissingFindThrows).
  testEffectEmptyItemsStillPrunes = {
    expr = rsc {
      routeros.config."/x" = {
        kind = "effect";
        find = item: {a = item.a;};
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

  testEffectMissingFindThrows = {
    expr = throws (rsc {
      routeros.config."/x" = {
        kind = "effect";
        items = [{a = "1";}];
      };
    });
    expected = true;
  };

  testEffectDuplicateFindThrows = {
    expr = throws (rsc {
      routeros.config."/x" = {
        kind = "effect";
        find = item: {a = item.a;};
        items = [
          {a = "1";}
          {
            a = "1";
            b = "2";
          }
        ];
      };
    });
    expected = true;
  };
}
