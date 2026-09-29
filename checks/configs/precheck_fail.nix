# Top-level `routeros.preCheck`: a failing check stops the run before any
# later command executes. The check prints a marker (proving script
# output is captured), then `:error`s; the entry below prints another
# marker from its `preScript` that must never appear. See
# routeros_test.py's "precheck_fail" subtest.
{
  routeros.preCheck = ''
    :put "routnix-test-precheck-ran"
    :error "routnix-test-precheck-failed"
  '';

  routeros.config."/system identity" = {
    kind = "settings";
    preScript = '':put "routnix-test-precheck-should-not-run"'';
    settings = {name = "routnix-test-precheck-should-not-apply";};
  };
}
