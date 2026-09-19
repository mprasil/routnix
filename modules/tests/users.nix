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
}
