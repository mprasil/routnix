{
  lib,
  config,
  ...
}: let
  inherit (lib) mkOption mkIf types filterAttrs mapAttrsToList optionalAttrs concatStringsSep attrValues concatMap splitString;
  inherit (lib.routnix) perPlatform;

  cfg = config.users.users;

  # Users declared with `create = false` are excluded from `/user`'s
  # `items` (there's nothing to `add` for them), so they need their
  # own `ignore` entry there to stay exempt from the mandatory prune
  # sweep -- otherwise declaring any other user would sweep them away.
  createFalseUsers = attrValues (filterAttrs (_: user: !user.create) cfg);

  # `sshPubKeys = null` (the default) means this user's keys aren't
  # routnix's concern: excluded from `/user ssh-keys`'s `items` and
  # `ignore`d instead, so whatever's already there is left alone. A
  # list -- including `[ ]` -- fully manages that user's keys,
  # independent of `create`, so managing keys for an existing,
  # otherwise-unmanaged account is supported.
  usersManagingSshKeys = filterAttrs (_: user: user.sshPubKeys != null) cfg;
  usersIgnoringSshKeys = filterAttrs (_: user: user.sshPubKeys == null) cfg;

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
      group = mkOption {
        type = types.str;
        default = "full";
        description = ''
          Permission group for a newly created user.
        '';
      };
      initialPassword = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          The password to set on a newly created user. It is only used when
          the account is first created; an existing account's password is
          left untouched.

          The string is stored in the nix store, so it's recommended to leave
          it undefined.

          If `null` (default) a random string is generated on-device.
        '';
      };
      sshPubKeys = mkOption {
        type = types.nullOr (types.listOf sshPubKeyType);
        default = null;
        description = ''
          SSH public keys this user should have. `null` (default)
          leaves this user's existing keys untouched; a list --
          including an empty one -- fully manages them, removing any
          key not declared here.
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
  options.users.enable = mkOption {
    type = types.bool;
    default = false;
    description = ''
      Whether routnix manages the router's user accounts and their SSH
      keys (`routeros.config."/user"` / `"/user ssh-keys"`). While
      disabled, `users.users` has no effect and neither path is
      touched.
    '';
  };

  options.users.users = mkOption {
    type =
      types.attrsOf (types.submodule
        userSubmodule);
    default = {};
    description = ''User configuration. '';
  };

  config = mkIf config.users.enable {
    routeros.config."/user" = {
      kind = "effect";
      find = item: {name = item.name;};
      ignore = map (user: {name = user.name;}) createFalseUsers;
      create = item: let
        passwordArg =
          if item ? initialPassword
          then "\"${item.initialPassword}\""
          else
            perPlatform config {
              routeros_v6 = v6_password_generator;
              routeros_v7 = "[:rndstr length=32 ]";
            };
      in "add name=\"${item.name}\" group=\"${item.group}\" password=${passwordArg}";
      items =
        mapAttrsToList
        (_: user:
          {inherit (user) name group;}
          // optionalAttrs (user.initialPassword != null) {inherit (user) initialPassword;})
        (filterAttrs (_: user: user.create) cfg);
    };
    routeros.config."/user ssh-keys" = {
      kind = "effect";
      after = ["/user"];
      find = item: let
        infoFieldName = perPlatform config {
          routeros_v6 = "key-owner";
          routeros_v7 = "info";
        };
      in {
        user = item.user;
        "${infoFieldName}" = item.hash;
      };
      ignore = map (user: {user = user.name;}) (attrValues usersIgnoringSshKeys);
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
        (attrValues usersManagingSshKeys);
    };
  };
}
