{
  rsc,
  throws,
  ...
}: {
  # -- kind = "unordered" ----------------------------------------------

  testUnorderedEmptyItemsRendersNothing = {
    expr = rsc {
      routeros.config."/x" = {
        kind = "unordered";
        items = [];
      };
    };
    expected = "\n";
  };

  testUnorderedWithoutPruneRendersPlainGuard = {
    expr = rsc {
      routeros.config."/x" = {
        kind = "unordered";
        items = [{a = "1";}];
      };
    };
    expected = ''
      /x
      :if ([/x print count-only where a="1"] = 0) do={
        add a="1"
      }
    ''; # trailing newline from renderConfig
  };

  testUnorderedWithPruneUsesIdTrackingAndSweep = {
    expr = rsc {
      routeros.config."/x" = {
        kind = "unordered";
        prune = true;
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

  # Same bug as testOrderedDerivedFindIncludesIgnoreOnlyField, for
  # `kind = "unordered"` with `prune = true`.
  testUnorderedPruneDerivedFindIncludesIgnoreOnlyField = {
    expr = rsc {
      routeros.config."/x" = {
        kind = "unordered";
        prune = true;
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
  testUnorderedPruneAccumulatesMultipleIgnorePredicates = {
    expr = rsc {
      routeros.config."/x" = {
        kind = "unordered";
        prune = true;
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

  # Without `prune = true`, `ignore` is already inert for
  # `kind = "unordered"` (not wired into `$ignore` or a prune sweep at
  # all -- see renderUnordered) -- derived `find` must stay as-is,
  # not fold in `ignore`'s fields either.
  testUnorderedWithoutPruneDerivedFindIgnoresIgnoreField = {
    expr = rsc {
      routeros.config."/x" = {
        kind = "unordered";
        ignore = [{c = "keep";}];
        items = [{a = "1";}];
      };
    };
    expected = ''
      /x
      :if ([/x print count-only where a="1"] = 0) do={
        add a="1"
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
