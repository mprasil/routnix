# kind = "effect" with `prune = true` and `ignore`. Mirrors
# "unordered_prune" but for the kind whose `create` runs commands other
# than a plain `add`: routeros_test.py's "effect_prune" subtest manually
# creates a "routnix-test-effect-prune-keep"-commented entry (matched by
# `ignore`) and a "routnix-test-effect-prune-manual"-commented one (not
# matched) before applying this, and expects only the latter to be
# swept -- while `create`'s `/system note` side effect (see
# "effect_basic") still only runs once.
{
  routeros.config."/ip firewall address-list" = {
    kind = "effect";
    prune = true;
    ignore = [{comment = "routnix-test-effect-prune-keep";}];
    find = item: {
      address = item.address;
      list = item.list;
    };
    create = item: ''
      /system note set note="${item.note}"
      add address="${item.address}" list="${item.list}" comment="${item.comment}"
    '';
    items = [
      {
        address = "10.10.10.50";
        list = "routnix-test-effect-prune";
        comment = "routnix-test-effect-prune-declared";
        note = "routnix-test-effect-prune-note";
      }
    ];
  };
}
