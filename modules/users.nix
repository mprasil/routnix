{
  lib,
  config,
  ...
}: let
  inherit (lib) mkOption types filterAttrs mapAttrsToList optionalAttrs concatStringsSep;
  inherit (lib.routnix) perPlatform;

  cfg = config.users.users;

  userSubmodule = {name, ...}: {
    options = {
      name = mkOption {
        type = types.str;
        default = name;
        description = ''
          The name of the user account on the device.
        '';
      };
      create = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Create the user if it does not already exist?
        '';
      };
      password = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          A password to set for newly created user.

          Note, that password updating is not implemented and the password
          string is stored in the nix store, so it's recommended to leave it
          undefined.

          If `null` (default) a random string is generated on-device.
        '';
      };
    };
  };

  # Yes, on ROS v6 we're generatig self-signed cert to create random string,
  # because we don't have :rndstr available. Yes it's horrible, ideas for
  # improvement wellcome.
  v6_password_generator = concatStringsSep " " [
    "["
    '':local c [/certificate add common-name=routnix-random name="routnix-random" key-usage=key-cert-sign,crl-sign ];''
    ''/certificate sign $c without-paging ;''
    '':local fingerprint [/certificate get $c fingerprint ];''
    ''/certificate remove $c;''
    ''$fingerprint''
    "]"
  ];
in {
  options.users.users = mkOption {
    type =
      types.attrsOf (types.submodule
        userSubmodule);
    default = {};
    description = ''User configuration. '';
  };

  config.routeros.config."/user" = {
    kind = "effect";
    find = item: {name = item.name;};
    create = item: let
      passwordArg =
        if item ? password
        then "\"${item.password}\""
        else
          perPlatform config {
            routeros_v6 = v6_password_generator;
            routeros_v7 = "[:rndstr length=32 ]";
          };
    in "add name=\"${item.name}\" password=${passwordArg}";
    items =
      mapAttrsToList
      (_: user:
        {inherit (user) name;}
        // optionalAttrs (user.password != null) {inherit (user) password;})
      (filterAttrs (_: user: user.create) cfg);
  };
}
