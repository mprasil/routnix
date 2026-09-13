{
  rsc,
  throws,
  ...
}: {
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
}
