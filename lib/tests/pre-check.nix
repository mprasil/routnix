{
  lib,
  rsc,
  routnix,
  ...
}: {
  # -- preCheck -------------------------------------------------------

  # `preCheck` is freehand `.rsc` text run at the very top, ahead of
  # every entry and separated from them by a blank line.
  testPreCheckRunsBeforeEntries = {
    expr = rsc {
      routeros.preCheck = ":put \"check\"";
      routeros.config."/x" = {
        kind = "settings";
        settings = {name = "r1";};
      };
    };
    expected = ''
      :put "check"

      /x
      set name="r1"
    '';
  };

  # ... ahead of an entry's own `preScript` too.
  testPreCheckRunsBeforeEntryPreScript = {
    expr = rsc {
      routeros.preCheck = ":put \"check\"";
      routeros.config."/x" = {
        kind = "settings";
        preScript = ":put \"entry\"";
        settings = {name = "r1";};
      };
    };
    expected = ''
      :put "check"

      :put "entry"

      /x
      set name="r1"
    '';
  };

  # A `preCheck` with no entries at all still renders.
  testPreCheckAloneRenders = {
    expr = rsc {routeros.preCheck = ":put \"check\"";};
    expected = ":put \"check\"\n";
  };

  # A `preCheck` of nothing but whitespace counts as none at all, the
  # same as an entry's `preScript`.
  testWhitespaceOnlyPreCheckRendersAsAbsent = {
    expr = rsc {
      routeros.preCheck = "\n  \n";
      routeros.config."/x" = {
        kind = "settings";
        settings = {name = "r1";};
      };
    };
    expected = "/x\nset name=\"r1\"\n";
  };

  # `preCheck` is `types.lines`, so several modules can each contribute
  # their own checks. Their order isn't guaranteed, so compare lines as
  # a set.
  testPreCheckMergesAcrossModules = {
    expr = lib.naturalSort
      (lib.splitString "\n" (routnix.evalConfig {
        modules = [
          {routeros.preCheck = ":put \"one\"";}
          {routeros.preCheck = ":put \"two\"";}
        ];
      }).rsc);
    expected = ["" ":put \"one\"" ":put \"two\""];
  };
}
