{
  evalConfig,
  evalSecrets,
  throws,
  ...
}: let
  fakeFile = builtins.toFile "fake-sops" "ciphertext";
  pwRef = {__routnixSecret = "pw";};
in {
  testSecretsEmptyByDefault = {
    expr = evalSecrets {};
    expected = {
      file = null;
      entries = {};
      hash = "";
    };
  };

  testEntriesWithoutFileThrows = {
    expr = throws (evalSecrets {
      routeros.secrets.entries.mailPassword = {};
    });
    expected = true;
  };

  testMissingFileThrows = {
    expr = throws (evalSecrets {
      routeros.secrets.file = /routnix-does-not-exist;
    });
    expected = true;
  };

  testReferenceDefaultsToEntryName = {
    expr = (evalSecrets {
      routeros.secrets.file = fakeFile;
      routeros.secrets.entries.mailPassword = {};
    })
    .entries.mailPassword;
    expected = {
      key = "mailPassword";
      reference = {__routnixSecret = "mailPassword";};
    };
  };

  testKeyIsASlashSeparatedPath = {
    expr = (evalSecrets {
      routeros.secrets.file = fakeFile;
      routeros.secrets.entries.mailPassword.key = "mail/password";
    })
    .entries.mailPassword.key;
    expected = "mail/password";
  };

  testHashCoversTheEncryptedFile = {
    expr = (evalSecrets {routeros.secrets.file = fakeFile;}).hash;
    expected = builtins.substring 0 7 (builtins.hashFile "sha256" fakeFile);
  };

  testConfigFieldAcceptsSecretReference = {
    expr = (evalConfig {
      routeros.secrets.file = fakeFile;
      routeros.secrets.entries.pw = {};
      routeros.config."/system note" = {
        kind = "settings";
        settings.note = pwRef;
      };
    })."/system note".settings.note;
    expected = pwRef;
  };

  testInitialPasswordAcceptsSecretReference = {
    expr = let
      entry = (evalConfig {
        routeros.secrets.file = fakeFile;
        routeros.secrets.entries.pw = {};
        users.enable = true;
        users.users.alice.initialPassword = pwRef;
      })."/user";
    in {
      item = (builtins.head entry.items).initialPassword;
      create = entry.create {
        name = "alice";
        group = "full";
        initialPassword = pwRef;
      };
    };
    expected = {
      item = pwRef;
      create = "add name=\"alice\" group=\"full\" password=($secrets->\"pw\")";
    };
  };
}
