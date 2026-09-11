# Same as ordered_basic.nix, except the "routnix-test-ordered-web"
# item's port changes (8080 -> 9090). Since kind = "ordered" identity is
# an item's whole field set, this must converge via add-new + prune-old
# rather than an in-place edit -- see routeros_test.py's "ordered_edit"
# subtest. "routnix-test-ordered-ssh" (tcp/22) is left untouched so the
# test's own SSH access survives the apply.
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
        "dst-port" = 9090;
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
