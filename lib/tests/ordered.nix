{
  rsc,
  throws,
  ...
}: {
  # -- kind = "ordered" -------------------------------------------------

  # Pruning is mandatory regardless of how many items are declared, so
  # an empty `items` list must still emit the prune sweep (and thus
  # remove anything left over at the path) rather than rendering
  # nothing at all for it.
  testOrderedEmptyItemsStillPrunes = {
    expr = rsc {
      routeros.config."/x" = {
        kind = "ordered";
        items = [];
      };
    };
    expected = ''
      /x
      :local ignore ({})
      :local managed ({})
      :foreach i in=[find] do={
        :if ([:find ($managed,$ignore) $i -1] < 0) do={ remove $i }
      }
    '';
  };

  # First item places itself at the front of a (possibly non-empty)
  # table; every later item places itself right after the previous
  # declared item's resolved id; a reorder pass and an unconditional
  # prune sweep always follow.
  testOrderedRendersPlaceBeforeChainReorderAndPrune = {
    expr = rsc {
      routeros.config."/x" = {
        kind = "ordered";
        items = [{a = "1";} {a = "2";}];
      };
    };
    expected = ''
      /x
      :local ignore ({})
      :local managed ({})
      {
        :local item [find where a="1"]
        :if ([:len $item] > 1) do={
          :put "routnix: find matched more than one entry in /x"
          :error "routnix-find-matched-multiple-entries"
        }
        :if ($item = "" || [:find $ignore $item -1] >= 0) do={
          :if ([print count-only] > 0) do={
          :set item [add place-before=([find]->0) a="1"]
        } else={
          :set item [add a="1"]
        }
        }
        :set managed ($managed, $item)
      }

      {
        :local item [find where a="2"]
        :if ([:len $item] > 1) do={
          :put "routnix: find matched more than one entry in /x"
          :error "routnix-find-matched-multiple-entries"
        }
        :if ($item = "" || [:find $ignore $item -1] >= 0) do={
          :set item [add place-before=([get ($managed->0)]->".nextid") a="2"]
        }
        :set managed ($managed, $item)
      }

      {
        :local first ($managed->0)
        :local firstExisting ([find]->0)
        :if ($first != $firstExisting) do={
          move $first destination=$firstExisting
        }
        :if ([:len $managed] > 1) do={
          :local prev $first
          :for i from=1 to=([:len $managed] - 1) do={
            :local cur ($managed->$i)
            :local dest ([get $prev]->".nextid")
            :if ($cur != $dest) do={
              move $cur destination=$dest
            }
            :set prev $cur
          }
        }
      }
      :foreach i in=[find] do={
        :if ([:find ($managed,$ignore) $i -1] < 0) do={ remove $i }
      }
    '';
  };

  testOrderedIgnoreResolvedBeforeAnyItem = {
    expr = rsc {
      routeros.config."/x" = {
        kind = "ordered";
        ignore = [{c = "keep";}];
        items = [{a = "1";}];
      };
    };
    expected = ''
      /x
      :local ignore ({})
      :set ignore ($ignore, [find where c="keep"])
      :local managed ({})
      {
        :local item [find where a="1" !c]
        :if ([:len $item] > 1) do={
          :put "routnix: find matched more than one entry in /x"
          :error "routnix-find-matched-multiple-entries"
        }
        :if ($item = "" || [:find $ignore $item -1] >= 0) do={
          :if ([print count-only] > 0) do={
          :set item [add place-before=([find]->0) a="1"]
        } else={
          :set item [add a="1"]
        }
        }
        :set managed ($managed, $item)
      }

      {
        :local first ($managed->0)
        :local firstExisting ([find]->0)
        :if ($first != $firstExisting) do={
          move $first destination=$firstExisting
        }
        :if ([:len $managed] > 1) do={
          :local prev $first
          :for i from=1 to=([:len $managed] - 1) do={
            :local cur ($managed->$i)
            :local dest ([get $prev]->".nextid")
            :if ($cur != $dest) do={
              move $cur destination=$dest
            }
            :set prev $cur
          }
        }
      }
      :foreach i in=[find] do={
        :if ([:find ($managed,$ignore) $i -1] < 0) do={ remove $i }
      }
    '';
  };

  # Regression test: a field only `ignore` sets (never any declared
  # item) must still show up as `!k` in the derived `find`, the same
  # way a field only *some* items set already does (see
  # testDeriveFindMissingFieldOnOtherItemRendersNull) -- otherwise an
  # `ignore`d entry that also happens to match the declared item's
  # own fields is indistinguishable from that item's entry once
  # routnix creates it alongside.
  testOrderedDerivedFindIncludesIgnoreOnlyField = {
    expr = rsc {
      routeros.config."/x" = {
        kind = "ordered";
        ignore = [{c = "keep";}];
        items = [{a = "1";}];
      };
    };
    expected = ''
      /x
      :local ignore ({})
      :set ignore ($ignore, [find where c="keep"])
      :local managed ({})
      {
        :local item [find where a="1" !c]
        :if ([:len $item] > 1) do={
          :put "routnix: find matched more than one entry in /x"
          :error "routnix-find-matched-multiple-entries"
        }
        :if ($item = "" || [:find $ignore $item -1] >= 0) do={
          :if ([print count-only] > 0) do={
          :set item [add place-before=([find]->0) a="1"]
        } else={
          :set item [add a="1"]
        }
        }
        :set managed ($managed, $item)
      }

      {
        :local first ($managed->0)
        :local firstExisting ([find]->0)
        :if ($first != $firstExisting) do={
          move $first destination=$firstExisting
        }
        :if ([:len $managed] > 1) do={
          :local prev $first
          :for i from=1 to=([:len $managed] - 1) do={
            :local cur ($managed->$i)
            :local dest ([get $prev]->".nextid")
            :if ($cur != $dest) do={
              move $cur destination=$dest
            }
            :set prev $cur
          }
        }
      }
      :foreach i in=[find] do={
        :if ([:find ($managed,$ignore) $i -1] < 0) do={ remove $i }
      }
    '';
  };

  # Same accumulation as testUnorderedPruneAccumulatesMultipleIgnorePredicates,
  # for `kind = "ordered"` (always pruned, so `ignore` is always
  # active here).
  testOrderedAccumulatesMultipleIgnorePredicates = {
    expr = rsc {
      routeros.config."/x" = {
        kind = "ordered";
        ignore = [{c = "keep";} {d = "also-keep";}];
        items = [{a = "1";}];
      };
    };
    expected = ''
      /x
      :local ignore ({})
      :set ignore ($ignore, [find where c="keep"])
      :set ignore ($ignore, [find where d="also-keep"])
      :local managed ({})
      {
        :local item [find where a="1" !c !d]
        :if ([:len $item] > 1) do={
          :put "routnix: find matched more than one entry in /x"
          :error "routnix-find-matched-multiple-entries"
        }
        :if ($item = "" || [:find $ignore $item -1] >= 0) do={
          :if ([print count-only] > 0) do={
          :set item [add place-before=([find]->0) a="1"]
        } else={
          :set item [add a="1"]
        }
        }
        :set managed ($managed, $item)
      }

      {
        :local first ($managed->0)
        :local firstExisting ([find]->0)
        :if ($first != $firstExisting) do={
          move $first destination=$firstExisting
        }
        :if ([:len $managed] > 1) do={
          :local prev $first
          :for i from=1 to=([:len $managed] - 1) do={
            :local cur ($managed->$i)
            :local dest ([get $prev]->".nextid")
            :if ($cur != $dest) do={
              move $cur destination=$dest
            }
            :set prev $cur
          }
        }
      }
      :foreach i in=[find] do={
        :if ([:find ($managed,$ignore) $i -1] < 0) do={ remove $i }
      }
    '';
  };

  testOrderedDuplicateDerivedFindThrows = {
    expr = throws (rsc {
      routeros.config."/x" = {
        kind = "ordered";
        items = [{a = "1";} {a = "1";}];
      };
    });
    expected = true;
  };
}
