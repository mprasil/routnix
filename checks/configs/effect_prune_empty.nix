# Regression check: kind = "effect" is documented as always pruning
# entries no longer declared, but an empty `items` list currently
# renders nothing at all for the whole path (see DESIGN.md's "entries
# that render to nothing are skipped"), skipping the mandatory prune
# sweep along with everything else. routeros_test.py's
# "effect_prune_empty" subtest manually adds an entry to
# /ip firewall address-list before applying this and expects the path
# to end up empty. `find` is required for kind = "effect" regardless
# of whether `items` is empty.
{
  routeros.config."/ip firewall address-list" = {
    kind = "effect";
    find = item: {
      address = item.address;
      list = item.list;
    };
    items = [];
  };
}
