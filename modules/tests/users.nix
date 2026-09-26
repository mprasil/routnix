{
  evalConfig,
  dataFields,
  lib,
  ...
}: let
  # Item/ignore comparisons below only look at the identifying field
  # (a user's `name` on `/user`, `user` on `/user ssh-keys`) rather than
  # full item equality -- keeps these tests decoupled from unrelated
  # details like the generated password or the SSH key content hash.
  userItemNames = entry: map (i: i.name) entry.items;
  userIgnoreNames = entry: map (i: i.name) entry.ignore;
  sshKeyItemUsers = entry: map (i: i.user) entry.items;
  sshKeyIgnoreUsers = entry: map (i: i.user) entry.ignore;

  inherit (lib) hasInfix;
in {
  testUsersDisabledByDefaultDeclaresNothing = {
    expr = evalConfig {users.users.alice = {};};
    expected = {};
  };

  testUsersEnabledWithNoUsersStillManagesBothPathsEmpty = {
    expr = lib.mapAttrs (_: dataFields) (evalConfig {users.enable = true;});
    expected = {
      "/user" = {
        kind = "effect";
        items = [];
        ignore = [];
      };
      "/user ssh-keys" = {
        kind = "effect";
        items = [];
        ignore = [];
      };
    };
  };

  testCreateTrueUserIsManagedNotIgnoredOnUserPath = {
    expr = let
      entry = (evalConfig {
        users.enable = true;
        users.users.alice = {};
      })."/user";
    in {
      names = userItemNames entry;
      ignored = userIgnoreNames entry;
    };
    expected = {
      names = ["alice"];
      ignored = [];
    };
  };

  testCreateFalseUserIsIgnoredNotManagedOnUserPath = {
    expr = let
      entry = (evalConfig {
        users.enable = true;
        users.users.admin = {create = false;};
      })."/user";
    in {
      names = userItemNames entry;
      ignored = userIgnoreNames entry;
    };
    expected = {
      names = [];
      ignored = ["admin"];
    };
  };

  # `create` only controls account creation: a `create = false` user's
  # declared `sshPubKeys` are still managed normally on
  # `/user ssh-keys`, independent of being ignored on `/user`.
  testCreateFalseUserWithDeclaredKeysIsManagedOnSshKeysPath = {
    expr = let
      entry = (evalConfig {
        users.enable = true;
        users.users.admin = {
          create = false;
          sshPubKeys = ["ssh-rsa AAAAB3NzaC1yc2E foo"];
        };
      })."/user ssh-keys";
    in {
      users = sshKeyItemUsers entry;
      ignored = sshKeyIgnoreUsers entry;
    };
    expected = {
      users = ["admin"];
      ignored = [];
    };
  };

  # `sshPubKeys = null` (the default): this user's keys aren't
  # routnix's concern at all -- ignored, not managed.
  testSshPubKeysNullIsIgnoredNotManagedOnSshKeysPath = {
    expr = let
      entry = (evalConfig {
        users.enable = true;
        users.users.alice = {};
      })."/user ssh-keys";
    in {
      users = sshKeyItemUsers entry;
      ignored = sshKeyIgnoreUsers entry;
    };
    expected = {
      users = [];
      ignored = ["alice"];
    };
  };

  # `sshPubKeys = [ ]` is a real declaration ("this user should have no
  # keys"), distinct from `null` ("don't touch this user's keys") -- it
  # must not end up in `ignore` either, so any of the user's existing
  # keys actually get removed by the mandatory prune sweep.
  testSshPubKeysEmptyListIsManagedNotIgnoredOnSshKeysPath = {
    expr = let
      entry = (evalConfig {
        users.enable = true;
        users.users.bob = {sshPubKeys = [];};
      })."/user ssh-keys";
    in {
      users = sshKeyItemUsers entry;
      ignored = sshKeyIgnoreUsers entry;
    };
    expected = {
      users = [];
      ignored = [];
    };
  };

  # `/user ssh-keys`'s `create` runs `import ... user="..."`, which
  # needs that account to already exist -- `/user` must always render
  # first, declared explicitly rather than relying on incidental
  # ordering between the two paths.
  testSshKeysPathDependsOnUserPath = {
    expr = (evalConfig {users.enable = true;})."/user ssh-keys".after;
    expected = ["/user"];
  };

  # `/user add` requires an explicit `group` argument on real RouterOS
  # (a missing one fails the whole `/import`) -- regression-anchored
  # here since that's the kind of bug pure-Nix render tests can't catch
  # on their own.
  testNewUserDefaultsToFullGroup = {
    expr = map (i: i.group) (evalConfig {
      users.enable = true;
      users.users.alice = {};
    })."/user".items;
    expected = ["full"];
  };

  testNewUserGroupIsConfigurable = {
    expr = map (i: i.group) (evalConfig {
      users.enable = true;
      users.users.alice = {group = "read";};
    })."/user".items;
    expected = ["read"];
  };

  testNewUserCreateIncludesGroup = {
    expr = hasInfix "group=\"read\"" ((evalConfig {
        users.enable = true;
        users.users.alice = {};
      })."/user".create {
        name = "alice";
        group = "read";
      });
    expected = true;
  };

  testNewUserInitialPasswordIsUsedWhenSet = {
    expr = hasInfix "password=\"hunter2\"" ((evalConfig {
        users.enable = true;
        users.users.alice = {initialPassword = "hunter2";};
      })."/user".create {
        name = "alice";
        group = "full";
        initialPassword = "hunter2";
      });
    expected = true;
  };

  # -- per-`device.platform` decisions -----------------------------
  #
  # `lib/tests/per_platform.nix` covers `perPlatform` itself; these
  # confirm modules/users.nix picks the right branch at each of its two
  # call sites. Whether the resulting `.rsc` text is actually valid on
  # real hardware is the integration check's job (an unavailable
  # command just fails `/import` there), not this one's.

  testNewUserPasswordUsesRndstrOnV7 = {
    expr = hasInfix "rndstr" ((evalConfig {
        device.platform = "routeros_v7";
        users.enable = true;
        users.users.alice = {};
      })."/user".create {
        name = "alice";
        group = "full";
      });
    expected = true;
  };

  testNewUserPasswordUsesCertTrickOnV6 = {
    expr = hasInfix "certificate" ((evalConfig {
        device.platform = "routeros_v6";
        users.enable = true;
        users.users.alice = {};
      })."/user".create {
        name = "alice";
        group = "full";
      });
    expected = true;
  };

  testSshKeysFindUsesInfoFieldOnV7 = {
    expr = (evalConfig {
      device.platform = "routeros_v7";
      users.enable = true;
      users.users.alice.sshPubKeys = ["ssh-rsa AAAAB3NzaC1yc2E foo"];
    })."/user ssh-keys".find {
      user = "alice";
      hash = "abc123456789";
    };
    expected = {
      user = "alice";
      info = "abc123456789";
    };
  };

  testSshKeysFindUsesKeyOwnerFieldOnV6 = {
    expr = (evalConfig {
      device.platform = "routeros_v6";
      users.enable = true;
      users.users.alice.sshPubKeys = ["ssh-rsa AAAAB3NzaC1yc2E foo"];
    })."/user ssh-keys".find {
      user = "alice";
      hash = "abc123456789";
    };
    expected = {
      user = "alice";
      "key-owner" = "abc123456789";
    };
  };

  testSshKeysCreateUsesFileAddOnV7 = {
    expr = hasInfix "/file add" ((evalConfig {
        device.platform = "routeros_v7";
        users.enable = true;
        users.users.alice.sshPubKeys = ["ssh-rsa AAAAB3NzaC1yc2E foo"];
      })."/user ssh-keys".create {
        user = "alice";
        hash = "abc123456789";
        key = "ssh-rsa AAAAB3NzaC1yc2E foo";
      });
    expected = true;
  };

  testSshKeysCreateUsesExecuteTrickOnV6 = {
    expr = hasInfix ":execute" ((evalConfig {
        device.platform = "routeros_v6";
        users.enable = true;
        users.users.alice.sshPubKeys = ["ssh-rsa AAAAB3NzaC1yc2E foo"];
      })."/user ssh-keys".create {
        user = "alice";
        hash = "abc123456789";
        key = "ssh-rsa AAAAB3NzaC1yc2E foo";
      });
    expected = true;
  };
}
