{
  renderValue,
  renderArgs,
  renderQuery,
  ...
}: {
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
}
