# Regression config for the ignore/derived-find overlap: the declared
# item below doesn't set `comment`, so its derived `find` is just
# chain=input action=accept protocol=icmp -- the same fields (plus
# `comment`) as the hand-made "routnix-test-ordered-ignore-overlap"
# entry that routeros_test.py's "ordered_ignore_overlap" subtest creates
# and matches via `ignore` before applying this, twice.
{
  routeros.config."/ip firewall filter" = {
    kind = "ordered";
    ignore = [{comment = "routnix-test-ordered-ignore-overlap";}];
    items = [
      {
        chain = "input";
        action = "accept";
        protocol = "icmp";
      }
    ];
  };
}
