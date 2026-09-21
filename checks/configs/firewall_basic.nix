# The `firewall.filter` module: named blocks compile down to one
# kind = "ordered" /ip firewall filter table, ordered among themselves
# by block-level `before`/`after`. routeros_test.py's
# "firewall_filter_*" subtests check the resulting rule order and
# idempotence.
#
# Declares an accept for tcp/22 (and established/related) because its
# mandatory prune sweep clears the whole table: without those, the
# test's own SSH access would be dropped. Runs last, so wiping whatever
# the earlier "ordered_*" group left behind is fine.
{
  firewall.filter.enable = true;

  firewall.filter.rules = {
    allowEstablished = {
      chain = "input";
      rules = [
        {
          action = "accept";
          "connection-state" = "established,related";
          comment = "routnix-test-fw-established";
        }
      ];
    };

    allowSsh = {
      after = ["allowEstablished"];
      chain = "input";
      rules = [
        {
          protocol = "tcp";
          "dst-port" = 22;
          action = "accept";
          comment = "routnix-test-fw-ssh";
        }
      ];
    };

    allowIcmp = {
      after = ["allowSsh"];
      chain = "input";
      rules = [
        {
          protocol = "icmp";
          action = "accept";
          comment = "routnix-test-fw-icmp";
        }
      ];
    };

    dropRest = {
      after = ["allowIcmp"];
      chain = "input";
      rules = [
        {
          action = "drop";
          comment = "routnix-test-fw-drop";
        }
      ];
    };
  };
}