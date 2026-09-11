# kind = "effect": `create` runs arbitrary .rsc text instead of a plain
# `add`. Each item's `create` here temporarily switches to
# /system note (an unrelated, absolute path) and then falls back to a
# plain, context-relative `add` -- exercising the claim that a
# fully-qualified one-off line doesn't permanently change the entry's
# own path context. See routeros_test.py's "effect_basic" subtest
# (apply, and idempotent reapply -- `create`, and its /system note side
# effect, must not rerun once `find` already matches).
{
  routeros.config."/ip firewall address-list" = {
    kind = "effect";
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
        address = "10.10.10.40";
        list = "routnix-test-effect";
        comment = "routnix-test-effect-1";
        note = "routnix-test-effect-note-1";
      }
      {
        address = "10.10.10.41";
        list = "routnix-test-effect";
        comment = "routnix-test-effect-2";
        note = "routnix-test-effect-note-2";
      }
    ];
  };
}
