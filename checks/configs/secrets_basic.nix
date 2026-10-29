# Secrets: a settings field, an unordered item whose derived `find`
# carries the reference, and a keyed path whose items carry the payload
# hash in `comment`. routeros_test.py's "secrets_*" subtests upload the
# payload with the real sops/curl uploader before applying this.
{config, lib, ...}: let
  entries = config.routeros.secrets.entries;
in {
  routeros.secrets.file = ../secrets/secrets.enc.yaml;
  routeros.secrets.entries = {
    mailPassword.key = "mail/password";
    wifiPassword.key = "wifi/password";
  };

  routeros.config."/system note" = {
    kind = "settings";
    settings.note = entries.mailPassword.reference;
  };

  routeros.config."/ip firewall address-list" = {
    kind = "unordered";
    items = [
      {
        address = "10.99.99.99";
        list = "routnix-test-secret";
        comment = entries.wifiPassword.reference;
      }
    ];
  };

  routeros.config."/ppp secret" = {
    kind = "keyed";
    key = item: {inherit (item) name;};
    items = lib.routnix.withSecretHash config.routeros.secrets.hash [
      {
        name = "routnix-test-secret-user";
        password = entries.mailPassword.reference;
        service = "any";
      }
      {
        name = "routnix-test-secret-user2";
        password = "routnix-test-literal";
        service = "any";
      }
    ];
  };
}
