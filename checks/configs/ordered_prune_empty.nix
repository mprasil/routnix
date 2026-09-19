# Regression check: kind = "ordered" is documented as always pruning
# entries no longer declared, but an empty `items` list currently
# renders nothing at all for the whole path (see DESIGN.md's "entries
# that render to nothing are skipped"), skipping the mandatory prune
# sweep along with everything else. routeros_test.py's
# "ordered_prune_empty" subtest manually adds an entry to
# /ip firewall filter before applying this and expects the path to end
# up empty.
{
  routeros.config."/ip firewall filter" = {
    kind = "ordered";
    items = [];
  };
}
