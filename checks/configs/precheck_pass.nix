# Top-level `routeros.preCheck`: freehand .rsc run ahead of any
# configuration. Here it records that it ran, and the config's own
# `set` still applies afterwards. See routeros_test.py's "precheck_pass"
# subtest.
{
  routeros.preCheck = ''
    /system note set note="routnix-test-precheck-ran"
  '';

  routeros.config."/system identity" = {
    kind = "settings";
    settings = {name = "routnix-test-precheck-pass";};
  };
}
