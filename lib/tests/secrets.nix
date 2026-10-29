{
  renderValue,
  renderArgs,
  renderQuery,
  routnix,
  rsc,
  ...
}: let
  inherit (routnix.routnix) secretReference withSecretHash;
  secret = secretReference;

  hostileName = "a\"b\\c$d?e\nf\tgλ";
in {
  # -- renderValue: secret references ---------------------------------

  testRenderValueSecret = {
    expr = renderValue (secret "foo");
    expected = ''($secrets->"foo")'';
  };

  # A secret renders the same whether it is an argument value or the
  # right-hand side of a `find where` clause.
  testRenderArgsSecret = {
    expr = renderArgs {
      name = secret "foo";
      port = 22;
    };
    expected = ''name=($secrets->"foo") port="22"'';
  };

  testRenderQuerySecret = {
    expr = renderQuery {
      name = secret "foo";
      absent = null;
    };
    expected = ''!absent name=($secrets->"foo")'';
  };

  # `:parse` executes the payload literal, so hostile names have to
  # survive a full escape round trip instead of injecting syntax.
  testRenderValueSecretEscapesHostileName = {
    expr = renderValue (secret hostileName);
    expected = ''($secrets->"a\"b\\c\$d\?e\nf\tgλ")'';
  };

  # -- prologue -------------------------------------------------------

  testSecretPrologueRunsAheadOfEverything = {
    expr = rsc {
      routeros.secrets.file = builtins.toFile "fake-sops" "ciphertext";
      routeros.secrets.entries.mailPassword.key = "mail/password";
      routeros.config."/system note" = {
        kind = "settings";
        settings.note = secretReference "mailPassword";
      };
    };
    expected = ''
      :local secrets [[:parse value=[/file get "routnix-secrets" value-name="contents"]]];

      /system note
      set note=($secrets->"mailPassword")
    '';
  };

  # -- per-path payload hash ------------------------------------------

  testWithSecretHashStampsEveryItemInThePath = {
    expr = withSecretHash "abc1234" [
      {name = "one"; password = secret "pw";}
      {name = "two"; mtu = 1500;}
    ];
    expected = [
      {name = "one"; password = secret "pw"; comment = "abc1234";}
      {name = "two"; mtu = 1500; comment = "abc1234";}
    ];
  };

  testWithSecretHashAppendsToUserComment = {
    expr = withSecretHash "abc1234" [
      {name = "one"; password = secret "pw"; comment = "uplink";}
    ];
    expected = [
      {name = "one"; password = secret "pw"; comment = "uplink abc1234";}
    ];
  };

  testWithSecretHashLeavesLiteralOnlyPathAlone = {
    expr = withSecretHash "abc1234" [
      {name = "one"; mtu = 1500;}
    ];
    expected = [
      {name = "one"; mtu = 1500;}
    ];
  };

  testWithSecretHashNoPayloadIsNoOp = {
    expr = withSecretHash "" [
      {name = "one"; password = secret "pw";}
    ];
    expected = [
      {name = "one"; password = secret "pw";}
    ];
  };
}
