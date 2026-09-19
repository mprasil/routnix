# The `users` module: managing a declared user's SSH keys. `admin`
# stays untouched (`create = false`, `sshPubKeys` left at its default
# `null`). routeros_test.py's "users_ssh_keys_add"/
# "users_ssh_keys_idempotent" subtests apply this.
{
  users.enable = true;
  users.users = {
    admin = {create = false;};
    keyuser = {
      sshPubKeys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDkSPJFx7J4EILPl6UUCuX/LktCSnHVdMJ2374xizd21dbYIpRn73PJ4G0B9nVxAu2EL8FPqilUBUMB19en0CiEWJjwsycoitBpe70yTUyrOTZvnSDjWrK2qWk1n7xYUSuvM6Apt968Mf47Rbpt4Nm5HEUT2uAR2JlcMlGt/jUIiLV69CDdXtM3lnuhmZCSOiDJh8mOhh/8GrPgfhEjobEGEH6+24uBxFESM/KWO/9rsSJvWUIRhTxZKHhzSY55tfomeo6f0r5/iw6Zkw+zHZBVCBWRlT9u7BkhWfkSk+wz97lgryb4zpaL+4ChlmxmpCK1p/LKraJEEzpr444BK5pz routnix-test-keyuser"
      ];
    };
  };
}
