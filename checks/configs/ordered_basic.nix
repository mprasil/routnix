# kind = "ordered" happy path: four declared items in
# /ip/firewall/filter, used by routeros_test.py's "ordered_*" subtests
# to check add-in-order placement, idempotence on reapply,
# drift-restoration, and field-edit convergence. Comments are prefixed
# distinctively so this path's pre-existing/default entries (if any)
# can't be confused with ours -- not that it matters much, since
# kind = "ordered" unconditionally prunes anything not declared here.
#
# The "routnix-test-ordered-ssh" item (tcp/22) is deliberately never
# touched by ordered_edit.nix: routeros_test.py's own SSH access to the
# VM depends on it staying in place across every "ordered_*" subtest,
# since the last item drops all otherwise-unmatched input traffic.
{
  routeros.config."/ip/firewall/filter" = {
    kind = "ordered";
    items = [
      {
        chain = "input";
        action = "accept";
        protocol = "icmp";
        comment = "routnix-test-ordered-icmp";
      }
      {
        chain = "input";
        action = "accept";
        protocol = "tcp";
        "dst-port" = 22;
        comment = "routnix-test-ordered-ssh";
      }
      {
        chain = "input";
        action = "accept";
        protocol = "tcp";
        "dst-port" = 8080;
        comment = "routnix-test-ordered-web";
      }
      {
        chain = "input";
        action = "drop";
        comment = "routnix-test-ordered-drop";
      }
    ];
  };
}
