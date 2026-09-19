# `create` only controls account creation: a `create = false` user's
# declared `sshPubKeys` are still fully managed on `/user ssh-keys`.
# routeros_test.py's "users_existing_user_keys" subtest manually
# creates "routnix-test-existinguser" before applying this and expects
# its key to be added while the account itself stays untouched. This
# deliberately isn't `admin`: attaching an SSH key to it would make
# RouterOS require key-based auth for that account, breaking the test
# harness's own password-based SSH access for every subsequent subtest.
{
  users.enable = true;
  users.users = {
    admin = {create = false;};
    routnix-test-existinguser = {
      create = false;
      sshPubKeys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDkSPJFx7J4EILPl6UUCuX/LktCSnHVdMJ2374xizd21dbYIpRn73PJ4G0B9nVxAu2EL8FPqilUBUMB19en0CiEWJjwsycoitBpe70yTUyrOTZvnSDjWrK2qWk1n7xYUSuvM6Apt968Mf47Rbpt4Nm5HEUT2uAR2JlcMlGt/jUIiLV69CDdXtM3lnuhmZCSOiDJh8mOhh/8GrPgfhEjobEGEH6+24uBxFESM/KWO/9rsSJvWUIRhTxZKHhzSY55tfomeo6f0r5/iw6Zkw+zHZBVCBWRlT9u7BkhWfkSk+wz97lgryb4zpaL+4ChlmxmpCK1p/LKraJEEzpr444BK5pz routnix-test-existinguser"
      ];
    };
  };
}
