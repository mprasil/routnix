# The `users` module: managing router accounts. `admin` is always
# declared with `create = false` here (and in every other users_*.nix
# config) since it's the account routeros_test.py itself connects over
# SSH as -- `/user`'s mandatory prune sweep must never remove it.
# routeros_test.py's "users_add"/"users_idempotent"/"users_prune"
# subtests apply this in sequence.
{
  users.enable = true;
  users.users = {
    admin = {create = false;};
    testuser = {};
  };
}
