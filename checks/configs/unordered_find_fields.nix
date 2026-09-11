# kind = "unordered" derived `find`: the two items below share every
# field except `comment`, which only the first one sets. Identity is
# derived per-item as `!comment` for the one that doesn't set it, so
# they must be treated as two distinct entries rather than colliding
# into one -- see routeros_test.py's "unordered_find_fields" subtest.
{
  routeros.config."/ip/firewall/address-list" = {
    kind = "unordered";
    items = [
      {
        address = "10.10.10.30";
        list = "routnix-test-fields";
        comment = "routnix-test-fields-has-comment";
      }
      {
        address = "10.10.10.31";
        list = "routnix-test-fields";
      }
    ];
  };
}
