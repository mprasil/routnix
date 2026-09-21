# Regression check: kind = "unordered" is documented as always
# pruning entries no longer declared, but an empty `items` list
# currently renders nothing at all for the whole path (see
# dr/rendering-conventions.md's "entries render to nothing are skipped
# entirely"), skipping the mandatory prune sweep along with everything
# else. routeros_test.py's
# "unordered_prune_empty" subtest manually adds an entry to
# /ip firewall address-list before applying this and expects the path
# to end up empty.
{
  routeros.config."/ip firewall address-list" = {
    kind = "unordered";
    items = [];
  };
}
