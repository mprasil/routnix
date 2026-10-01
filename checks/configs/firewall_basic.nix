# The `firewall.filter` module: named blocks compile down to one
# kind = "ordered" table per managed family, ordered among themselves
# by block-level `before`/`after`. routeros_test.py's
# "firewall_filter_*" subtests check the resulting rule order and
# idempotence in both tables.
#
# Declares an accept for tcp/22 (and established/related) because its
# mandatory prune sweep clears the whole table: without those, the
# test's own SSH access would be dropped. Runs last, so wiping whatever
# the earlier "ordered_*" group left behind is fine.
{
  config,
  lib,
  ...
}: let
  inherit (lib.routnix) perPlatform;

  # ipv6 is a separately installable package on RouterOS v6 (and
  # enabling it needs a reboot), so the v6 CHR image can't manage
  # /ipv6 firewall filter; v7 has it built in.
  managesIpv6 = perPlatform config {
    routeros_v6 = false;
    routeros_v7 = true;
  };
in {
  firewall.filter.enable = true;
  firewall.filter.family =
    if managesIpv6
    then "both"
    else "ipv4only";

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

    # `icmp` is an ipv4 protocol; the ipv6 table gets its own icmpv6 block.
    allowIcmp = {
      family = "ipv4";
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
  }
  // lib.optionalAttrs managesIpv6 {
    allowIcmp6 = {
      family = "ipv6";
      after = ["allowSsh"];
      before = ["dropRest"];
      chain = "input";
      rules = [
        {
          protocol = "icmpv6";
          action = "accept";
          comment = "routnix-test-fw-icmp6";
        }
      ];
    };
  };
}