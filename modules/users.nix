{
  lib,
  config,
  ...
}: let
  inherit (lib) mkOption types filterAttrs mapAttrsToList optionalAttrs concatStringsSep attrValues concatMap splitString;
  inherit (lib.routnix) perPlatform;

  cfg = config.users.users;

  # authorized_keys-style single line: a key type RouterOS actually
  # supports on the configured platform, a base64 blob, and an optional
  # trailing comment. Ed25519 requires RouterOS v7 (7.12+); RSA and the
  # legacy DSA are supported on both. (though DSA is not recommended)
  sshPubKeyTypesPattern = perPlatform config {
    routeros_v6 = "(ssh-rsa|ssh-dss)";
    routeros_v7 = "(ssh-rsa|ssh-dss|ssh-ed25519)";
  };
  sshPubKeyType = types.strMatching "${sshPubKeyTypesPattern} [A-Za-z0-9+/]+=*( .*)?";

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
        default = true;
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
      sshPubKeys = mkOption {
        type = types.listOf sshPubKeyType;
        default = [];
        description = ''
          List of ssh public keys to set up for user to be able to log in with.
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

  # Short, non-cryptographic checksum of a pubkey's content, used as the
  # ssh-keys entry's `info` field to detect whether a declared key is
  # already present.
  sshPubKeyHash = key: builtins.substring 0 12 (builtins.hashString "md5" key);

  # RouterOS reads a pubkey file's third whitespace-separated field as the
  # entry's `info`, so any comment already in the key is dropped and
  # replaced with our own hash to keep `info` predictable.
  sshPubKeyFileContents = key: let
    parts = splitString " " key;
  in "${builtins.elemAt parts 0} ${builtins.elemAt parts 1} ${sshPubKeyHash key}";
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
  config.routeros.config."/user ssh-keys" = {
    kind = "effect";
    find = item: let
      infoFieldName = perPlatform config {
        routeros_v6 = "key-owner";
        routeros_v7 = "info";
      };
    in {
      user = item.user;
      "${infoFieldName}" = item.hash;
    };
    create = item: let
      fileName = "routnix-${item.user}-${item.hash}.pub";
      fileCreationCommand = perPlatform config {
        routeros_v6 = '':execute ":put \"${sshPubKeyFileContents item.key}\"" file="${fileName}\00"'';
        routeros_v7 = ''/file add name="${fileName}" contents="${sshPubKeyFileContents item.key}"'';
      };
    in ''
      ${fileCreationCommand}
      import public-key-file="${fileName}" user="${item.user}"
    '';
    items =
      concatMap
      (user:
        map
        (key: {
          user = user.name;
          key = key;
          hash = sshPubKeyHash key;
        })
        user.sshPubKeys)
      (attrValues (filterAttrs (_: user: user.create) cfg));
  };
}
