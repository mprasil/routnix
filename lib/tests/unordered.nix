{
  rsc,
  throws,
  ...
}: {
  # -- kind = "unordered" ----------------------------------------------

  # Pruning is mandatory regardless of how many items are declared, so
  # an empty `items` list must still emit the prune sweep (and thus
  # remove anything left over at the path) rather than rendering
  # nothing at all for it.
  testUnorderedEmptyItemsStillPrunes = {
    expr = rsc {
      routeros.config."/x" = {
        kind = "unordered";
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

  testUnorderedUsesIdTrackingAndSweep = {
    expr = rsc {
      routeros.config."/x" = {
        kind = "unordered";
        ignore = [{c = "keep";}];
        items = [{a = "1";}];
      };
    };
    expected = ''
      /x
      :local ignore ({})
      :set ignore ($ignore, [/x find where c="keep"])
      :local managed ({})
      {
        :local item [/x find where a="1" !c]
        :if ([:len $item] > 1) do={
            :error ("routnix: find matched more than one entry in /x")
        }
        :if ($item = "" || [:find $ignore $item -1] >= 0) do={
            :set item [add a="1"]
        }
        :set managed ($managed, $item)
      }
      :foreach i in=[/x find] do={
        :if ([:find ($managed,$ignore) $i -1] < 0) do={ /x remove $i }
      }
    '';
  };

  # Regression test: a field only `ignore` sets (never any declared
  # item) must still show up in the derived `find`'s null-padding, or
  # an `ignore`d entry that also happens to match a declared item's
  # other fields could collide with it -- see
  # testOrderedDerivedFindIncludesIgnoreOnlyField for the `kind =
  # "ordered"` equivalent.
  testUnorderedDerivedFindIncludesIgnoreOnlyField = {
    expr = rsc {
      routeros.config."/x" = {
        kind = "unordered";
        ignore = [{c = "keep";}];
        items = [{a = "1";}];
      };
    };
    expected = ''
      /x
      :local ignore ({})
      :set ignore ($ignore, [/x find where c="keep"])
      :local managed ({})
      {
        :local item [/x find where a="1" !c]
        :if ([:len $item] > 1) do={
            :error ("routnix: find matched more than one entry in /x")
        }
        :if ($item = "" || [:find $ignore $item -1] >= 0) do={
            :set item [add a="1"]
        }
        :set managed ($managed, $item)
      }
      :foreach i in=[/x find] do={
        :if ([:find ($managed,$ignore) $i -1] < 0) do={ /x remove $i }
      }
    '';
  };

  # `ignore` predicates each resolve to their own `find` and get
  # appended onto the same `$ignore` list (`($ignore, [...])`, not
  # overwritten) -- with two predicates on different fields, both
  # fields must show up in the derived `find`'s null-padding, and
  # there must be one accumulating `:set ignore` line per predicate.
  testUnorderedAccumulatesMultipleIgnorePredicates = {
    expr = rsc {
      routeros.config."/x" = {
        kind = "unordered";
        ignore = [{c = "keep";} {d = "also-keep";}];
        items = [{a = "1";}];
      };
    };
    expected = ''
      /x
      :local ignore ({})
      :set ignore ($ignore, [/x find where c="keep"])
      :set ignore ($ignore, [/x find where d="also-keep"])
      :local managed ({})
      {
        :local item [/x find where a="1" !c !d]
        :if ([:len $item] > 1) do={
            :error ("routnix: find matched more than one entry in /x")
        }
        :if ($item = "" || [:find $ignore $item -1] >= 0) do={
            :set item [add a="1"]
        }
        :set managed ($managed, $item)
      }
      :foreach i in=[/x find] do={
        :if ([:find ($managed,$ignore) $i -1] < 0) do={ /x remove $i }
      }
    '';
  };

  testUnorderedDuplicateDerivedFindThrows = {
    expr = throws (rsc {
      routeros.config."/x" = {
        kind = "unordered";
        items = [{a = "1";} {a = "1";}];
      };
    });
    expected = true;
  };
}
