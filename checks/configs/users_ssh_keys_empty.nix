# Regression check: `sshPubKeys = [ ]` is a real declaration ("this
# user should have no keys"), distinct from the default `null` ("don't
# touch this user's keys") -- it must fully manage (and here, wipe)
# keyuser's keys, not leave them untouched. routeros_test.py's
# "users_ssh_keys_wipe" subtest applies this after
# users_ssh_keys_basic.nix and expects keyuser's key to be gone.
{
  users.enable = true;
  users.users = {
    admin = {create = false;};
    keyuser = {sshPubKeys = [];};
  };
}
