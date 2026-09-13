# kind = "ordered" pruning is mandatory; `ignore` is the escape hatch
# for entries managed by hand/another tool. routeros_test.py's
# "ordered_ignore" subtest manually creates a "routnix-test-ordered-keep"
# and a "routnix-test-ordered-keep-2" entry (each matched by a
# different `ignore` predicate below, to check both predicates'
# matches accumulate into the same prune-sweep exemption) and a
# "routnix-test-ordered-manual" one (not matched) before applying this,
# and expects the former two to survive the prune sweep and the latter
# to be removed.
{
  routeros.config."/ip firewall filter" = {
    kind = "ordered";
    ignore = [
      {comment = "routnix-test-ordered-keep";}
      {comment = "routnix-test-ordered-keep-2";}
    ];
    items = [
      {
        chain = "input";
        action = "accept";
        protocol = "icmp";
        comment = "routnix-test-ordered-icmp";
      }
    ];
  };
}
