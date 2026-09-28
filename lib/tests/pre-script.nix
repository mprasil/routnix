{
  rsc,
  throws,
  ...
}: {
  # -- preScript ------------------------------------------------------

  # `preScript` is freehand `.rsc` text, run before the entry's path
  # header and separated from the rest of the entry by a blank line. An
  # indented string literal's trailing newline is trimmed, rather than
  # rendering as a blank line of its own.
  testPreScriptRunsBeforePathHeader = {
    expr = rsc {
      routeros.config."/x" = {
        kind = "settings";
        preScript = ''
          /x setup
          :put "x set up"
        '';
        settings = {name = "r1";};
      };
    };
    expected = ''
      /x setup
      :put "x set up"

      /x
      set name="r1"
    '';
  };

  # Same for a table kind, where the path header is followed by the
  # `find`/`add`/prune sweep.
  testPreScriptRunsBeforeTableEntries = {
    expr = rsc {
      routeros.config."/x" = {
        kind = "unordered";
        preScript = ":put \"pre\"";
        items = [{a = "1";}];
      };
    };
    expected = ''
      :put "pre"

      /x
      :local ignore ({})
      :local managed ({})
      {
        :local item [/x find where a="1"]
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

  # A `preScript` of nothing but whitespace counts as no `preScript` at
  # all, rather than rendering as a blank line ahead of the path.
  testPreScriptWhitespaceOnlyRendersAsAbsent = {
    expr = rsc {
      routeros.config."/x" = {
        kind = "settings";
        preScript = "\n  \n";
        settings = {name = "r1";};
      };
    };
    expected = "/x\nset name=\"r1\"\n";
  };

  # An entry with a `preScript` but nothing of its own to render still
  # runs the `preScript` -- here a `"settings"` entry with no fields.
  testPreScriptRendersWithEmptySettings = {
    expr = rsc {
      routeros.config."/x" = {
        kind = "settings";
        preScript = ":put \"pre\"";
        settings = {};
      };
    };
    expected = ":put \"pre\"\n";
  };

  # ... and an `"inventory"` entry with no items, which otherwise
  # renders nothing at all.
  testPreScriptRendersWithEmptyInventoryItems = {
    expr = rsc {
      routeros.config."/x" = {
        kind = "inventory";
        preScript = ":put \"pre\"";
        find = item: {a = item.a;};
        configure = item: "set $item name=x";
        items = [];
      };
    };
    expected = ":put \"pre\"\n";
  };

  # A `preScript` doesn't make an invalid entry valid: the
  # missing-`find` guard still fires.
  testPreScriptDoesNotSkipValidation = {
    expr = throws (rsc {
      routeros.config."/x" = {
        kind = "inventory";
        preScript = ":put \"pre\"";
        configure = item: "set $item name=x";
        items = [{a = "1";}];
      };
    });
    expected = true;
  };
}
