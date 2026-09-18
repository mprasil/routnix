# kind = "unordered" with `ignore`. Mirrors the "ordered_ignore" case:
# routeros_test.py's "unordered_prune" subtest manually creates a
# "routnix-test-prune-keep"-commented entry (matched by `ignore`) and a
# "routnix-test-prune-manual"-commented one (not matched) before
# applying this, and expects only the latter to be swept.
{
  routeros.config."/ip firewall address-list" = {
    kind = "unordered";
    ignore = [{comment = "routnix-test-prune-keep";}];
    items = [
      {
        address = "10.10.10.20";
        list = "routnix-test-prune";
        comment = "routnix-test-prune-declared";
      }
    ];
  };
}
