{
  rsc,
  throws,
  routnix,
  ...
}: {
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
    expr = throws (routnix.evalConfig {modules = [../../examples/cycle.nix];}).rsc;
    expected = true;
  };
}
