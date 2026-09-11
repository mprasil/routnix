# kind = "ordered" pruning is mandatory; `ignore` is the escape hatch
# for entries managed by hand/another tool. routeros_test.py's
# "ordered_ignore" subtest manually creates a "routnix-test-ordered-keep"
# entry (matched by `ignore` below) and a "routnix-test-ordered-manual"
# one (not matched) before applying this, and expects the former to
# survive the prune sweep and the latter to be removed.
{
  routeros.config."/ip/firewall/filter" = {
    kind = "ordered";
    ignore = [{comment = "routnix-test-ordered-keep";}];
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
