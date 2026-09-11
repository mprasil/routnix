# kind = "settings" happy path: a single `set` against a singleton
# config object. /system identity is used since it's safe to change
# without disrupting the VM's reachability -- see routeros_test.py's
# "settings_basic" subtest (apply + idempotent reapply).
{
  routeros.config."/system identity" = {
    kind = "settings";
    settings = {name = "routnix-test-router";};
  };
}
