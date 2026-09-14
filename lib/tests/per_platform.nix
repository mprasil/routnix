{
  perPlatform,
  throws,
  ...
}: {
  # -- perPlatform ------------------------------------------------------

  testPerPlatformPicksMatchingPlatform = {
    expr = perPlatform {device.platform = "routeros_v7";} {
      routeros_v6 = "a";
      routeros_v7 = "b";
    };
    expected = "b";
  };

  testPerPlatformThrowsOnUnlistedPlatform = {
    expr = throws (perPlatform {device.platform = "routeros_v6";} {
      routeros_v7 = "b";
    });
    expected = true;
  };
}
