{config, lib, ...}: let
  inherit (lib) mkOption types;
  inherit (lib.routnix) secretReference;

  cfg = config.routeros.secrets;

  entryModule = {name, ...}: {
    options = {
      key = mkOption {
        type = types.str;
        default = name;
        description = ''
          Path to this secret in the sops file, with components separated
          by `/`, for example `"mail/password"`. Defaults to the entry
          name.
        '';
      };

      reference = mkOption {
        type = types.raw;
        readOnly = true;
        default = secretReference name;
        description = ''
          Value to use wherever a secret is accepted, for example
          `config.routeros.secrets.entries.mailPassword.reference`.
        '';
      };
    };
  };
in {
  options.routeros.secrets = {
    file = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Encrypted sops file holding the secrets declared in `entries`.
        The file is committed as ciphertext and decrypted on the machine
        running the deploy. `null` means no secrets are used.
      '';
    };

    entries = mkOption {
      type = types.attrsOf (types.submodule entryModule);
      default = {};
      description = ''
        Secrets available to `routeros.config`, keyed by name. The sops
        document may nest; each entry's `key` selects the value to read.
      '';
    };

    hash = mkOption {
      type = types.str;
      readOnly = true;
      default =
        if cfg.file == null
        then ""
        else builtins.substring 0 7 (builtins.hashFile "sha256" cfg.file);
      description = ''
        Short hash of the encrypted `file`, or `""` when no file is set.
        It changes when the encrypted file changes, so a `keyed` item's
        `comment` can include it and be re-`set` after a rotation.
      '';
    };
  };

  config.assertions = [
    {
      assertion = cfg.entries == {} || cfg.file != null;
      message = "routeros.secrets.entries is set but routeros.secrets.file is not.";
    }
    {
      assertion = cfg.file == null || builtins.pathExists cfg.file;
      message = "routeros.secrets.file does not exist: ${toString cfg.file}";
    }
  ];
}
