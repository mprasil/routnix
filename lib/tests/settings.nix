{
  rsc,
  throws,
  ...
}: {
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
}
