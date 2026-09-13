{deriveFind, ...}: {
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
}
