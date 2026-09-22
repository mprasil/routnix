# kind = "inventory": an entry that already exists, bound to the
# hardware, is located by `find` and adjusted in place -- here setting
# ether1's comment -- with nothing added or removed. See
# routeros_test.py's "inventory_configure"/"inventory_idempotent"
# subtests.
{
  routeros.config."/interface ethernet" = {
    kind = "inventory";
    find = item: {"default-name" = item.defaultName;};
    configure = item: "set $item comment=\"${item.comment}\"";
    items = [{defaultName = "ether1"; comment = "routnix-test-inventory";}];
  };
}