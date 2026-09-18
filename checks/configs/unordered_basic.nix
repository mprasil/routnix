# kind = "unordered" happy path, no `ignore`: used for add and
# idempotence-on-reapply subtests (routeros_test.py's "unordered_basic").
{
  routeros.config."/ip firewall address-list" = {
    kind = "unordered";
    items = [
      {
        address = "10.10.10.10";
        list = "routnix-test-basic";
      }
    ];
  };
}
