{
  lib,
  pkgs,
}: let
  inherit (import ./render_rsc/common.nix {inherit lib;}) renderValue renderArgs renderQuery;
  inherit (import ./render_rsc/unordered.nix {inherit lib;}) deriveFind;
  routnix = import ./default.nix {inherit lib;};

  # Evaluates a small inline `routeros.config` module through the full
  # `evalConfig` pipeline (module eval -> toposort -> render).
  eval = module: routnix.evalConfig {modules = [module];};
  rsc = module: (eval module).rsc;

  # True iff fully evaluating `expr` throws.
  throws = expr: !(builtins.tryEval (builtins.deepSeq expr true)).success;

  # Format failures nicely
  diffFailures = f: let
    toDiffableString = v:
      if builtins.typeOf v == "string"
      then v
      else lib.generators.toPretty {} v;
  in
    builtins.readFile (
      pkgs.runCommand "diff-error" {} ''
        cat > expected.txt <<'ENDOFTESTSTRING'
        ${toDiffableString f.expected}
        ENDOFTESTSTRING
        cat > got.txt <<'ENDOFTESTSTRING'
        ${toDiffableString f.result}
        ENDOFTESTSTRING
        echo "#### FAILED TEST: ${f.name}" > $out
        echo "## Test Result:" >> $out
        cat got.txt >> $out
        echo >> $out
        echo "## Difference:" >> $out
        ${pkgs.diffutils}/bin/diff \
          --color=always \
          --label "Test Result" \
          --label "Expected" \
          -u  got.txt expected.txt >> "$out" || true
      ''
    );

  tests = {
    # -- renderValue: scalar rendering rules ---------------------------

    testRenderValueBoolTrue = {
      expr = renderValue true;
      expected = "yes";
    };
    testRenderValueBoolFalse = {
      expr = renderValue false;
      expected = "no";
    };
    # NOTE: DESIGN.md documents `int` as rendering bare (`22`, not
    # `"22"`), but the current single `renderValue` implementation
    # quotes every non-bool scalar, `int` included, everywhere (`args`
    # and `where`-clause queries alike). This test pins down the actual
    # current behavior, not the documented one.
    testRenderValueInt = {
      expr = renderValue 22;
      expected = ''"22"'';
    };
    testRenderValueStr = {
      expr = renderValue "eth0";
      expected = ''"eth0"'';
    };

    testRenderArgsSortsKeysAndRendersEachType = {
      expr = renderArgs {
        z = true;
        a = 1;
        m = "x";
      };
      expected = ''a="1" m="x" z=yes'';
    };

    testRenderQueryAbsentFieldRendersBang = {
      expr = renderQuery {
        a = "x";
        b = null;
      };
      expected = ''a="x" !b'';
    };

    # -- deriveFind: identity derived from an item's own fields --------

    testDeriveFindPlainFields = {
      expr =
        deriveFind [
          {
            a = "1";
            b = "2";
          }
        ] {
          a = "1";
          b = "2";
        };
      expected = {
        a = "1";
        b = "2";
      };
    };

    # A field only *some* items in the list set must still show up
    # (as `null`, i.e. `!k`) for items that don't set it, so they don't
    # collapse into the same query as an item that does.
    testDeriveFindMissingFieldOnOtherItemRendersNull = {
      expr = deriveFind [
        {a = "1";}
        {
          a = "2";
          b = "x";
        }
      ] {a = "1";};
      expected = {
        a = "1";
        b = null;
      };
    };

    # -- kind = "settings" ----------------------------------------------

    testSettingsEmptyRendersNothing = {
      expr = rsc {
        routeros.config."/x" = {
          kind = "settings";
          settings = {};
        };
      };
      expected = "\n";
    };

    testSettingsRendersSingleSet = {
      expr = rsc {
        routeros.config."/system identity" = {
          kind = "settings";
          settings = {name = "r1";};
        };
      };
      expected = "/system identity\nset name=\"r1\"\n";
    };

    testPruneOnSettingsThrows = {
      expr = throws (rsc {
        routeros.config."/x" = {
          kind = "settings";
          prune = true;
        };
      });
      expected = true;
    };

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
    # `kind = "unordered"` with `prune = true` (the only case where
    # `ignore` is actually wired in for this kind).
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

    # -- kind = "effect" --------------------------------------------------

    testEffectUsesCustomCreateUnderGuard = {
      expr = rsc {
        routeros.config."/x" = {
          kind = "effect";
          find = item: {a = item.a;};
          create = item: "custom ${item.a}";
          items = [{a = "1";}];
        };
      };
      expected = ''
        /x
        :if ([/x print count-only where a="1"] = 0) do={
          custom 1
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

    testPruneOnEffectThrows = {
      expr = throws (rsc {
        routeros.config."/x" = {
          kind = "effect";
          prune = true;
          find = item: {a = item.a;};
          items = [{a = "1";}];
        };
      });
      expected = true;
    };

    # -- kind = "ordered" -------------------------------------------------

    testOrderedEmptyItemsRendersNothing = {
      expr = rsc {
        routeros.config."/x" = {
          kind = "ordered";
          items = [];
        };
      };
      expected = "\n";
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
            :error ("routnix: find matched more than one entry in /x")
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
            :error ("routnix: find matched more than one entry in /x")
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
            :error ("routnix: find matched more than one entry in /x")
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
            :error ("routnix: find matched more than one entry in /x")
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
            :error ("routnix: find matched more than one entry in /x")
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

    # -- ordering between whole paths (`before`/`after`, toposort) ------

    testBeforeOrdersEntryEarlierInOutput = {
      expr = rsc {
        routeros.config."/a" = {
          kind = "settings";
          settings = {x = "1";};
          before = ["/b"];
        };
        routeros.config."/b" = {
          kind = "settings";
          settings = {y = "2";};
        };
      };
      expected = "/a\nset x=\"1\"\n\n/b\nset y=\"2\"\n";
    };

    testAfterOrdersEntryLaterInOutput = {
      expr = rsc {
        routeros.config."/a" = {
          kind = "settings";
          settings = {x = "1";};
        };
        routeros.config."/b" = {
          kind = "settings";
          settings = {y = "2";};
          after = ["/a"];
        };
      };
      expected = "/a\nset x=\"1\"\n\n/b\nset y=\"2\"\n";
    };

    testDependencyCycleThrows = {
      expr = throws (rsc {
        routeros.config."/a" = {
          kind = "settings";
          settings = {};
          after = ["/b"];
        };
        routeros.config."/b" = {
          kind = "settings";
          settings = {};
          after = ["/a"];
        };
      });
      expected = true;
    };

    testCycleExampleThrows = {
      expr = throws (routnix.evalConfig {modules = [../examples/cycle.nix];}).rsc;
      expected = true;
    };
  };

  failures = lib.runTests tests;
in
  if failures == []
  then null
  else
    throw ''
      routnix: ${toString (builtins.length failures)} lib/tests.nix test(s) failed:
      ${lib.concatMapStringsSep "\n\n" diffFailures failures}
    ''
