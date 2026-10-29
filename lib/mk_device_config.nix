{evalConfig}:
# Evaluates a router's `modules` (via `evalConfig`) and packages the
# rendered `.rsc` as a derivation, with an `apply` and a `vm` wrapper
# attached via `passthru`:
#
#   mkDeviceConfig { inherit pkgs; name = "home-router"; modules = [ ./home-router.nix ]; }
#
# `apply` scps the `.rsc` to `<user@host>` (a runtime argument, defaulting
# to `host` when one is set), uploads the secret payload when the config
# declares one, and runs `/import` over ssh, removing the file from the
# router afterwards. `--copy-only` copies only the `.rsc`;
# `--copy-with-secrets` copies the `.rsc` and the payload without
# importing. Auth, host keys, and identity are left entirely to the
# caller's own ssh/scp config and agent; `sshOptions`/`scpOptions`/
# `curlOptions` (and the `ROUTNIX_SSH_OPTS`/`ROUTNIX_SCP_OPTS` env vars)
# pass extra options through to `ssh`/`scp`/`curl` (e.g. a non-default port
# or identity file), and `sops`/`curl` override the packages the payload
# uploader uses. The uploaded file is named after the `.rsc` store path
# (`<hash>-<name>.rsc`).
#
# `vm` boots a RouterOS CHR VM with that same `.rsc` applied to it over
# SSH, for trying the configuration out without a physical router (see
# `mk_vm.nix`); its image, SSH port, and console handling come from the
# `vm` argument below.
{
  pkgs,
  modules,
  name ? "routnix",
  host ? null,
  openssh ? pkgs.openssh,
  sshOptions ? [],
  scpOptions ? [],
  sops ? pkgs.sops,
  curl ? pkgs.curl,
  curlOptions ? [],
  vm ? {},
}: let
  inherit (pkgs) lib;

  evaluated = evalConfig {inherit modules;};
  rscFile = pkgs.writeText "${name}.rsc" evaluated.rsc;
  remoteName = builtins.baseNameOf rscFile;
  defaultHost = if host == null then "" else host;
  hostArg = if host == null then "<user@host>" else "[<user@host>]";

  mkSecretUploader = args:
    (import ./secret_upload.nix {inherit pkgs;}) (
      {inherit (evaluated) secrets;}
      // args
    );

  secretUploader = mkSecretUploader {inherit sops curl curlOptions;};
  # A fresh VM has an unknown host key, and its admin account accepts
  # empty-password "none" auth.
  vmSecretUploader = mkSecretUploader {
    inherit sops curl;
    curlOptions = ["-k" "-u" "admin:"];
  };
  secretUploaderScript =
    if secretUploader == null
    then ""
    else "${secretUploader}/bin/routnix-upload-secrets";

  vmConfig =
    {
      rosVersion = "stable-v7";
      image = null;
      sshPort = 2222;
      console = false;
    }
    // vm;

  versions = import ../ros_versions.nix;

  # The rendered `.rsc` follows `device.platform`, so a VM of a different
  # RouterOS major version would exercise the wrong branch.
  vmImage =
    if vmConfig.image != null
    then vmConfig.image
    else if !(versions ? ${vmConfig.rosVersion})
    then
      throw ''
        routnix: vm.rosVersion "${vmConfig.rosVersion}" is not a known RouterOS version -- expected one of: ${lib.concatStringsSep ", " (builtins.attrNames versions)}
      ''
    else let
      imageMajor = lib.head (lib.splitString "." versions.${vmConfig.rosVersion}.version);
      platformMajor = lib.removePrefix "routeros_v" evaluated.config.device.platform;
    in
      if imageMajor == platformMajor
      then (import ../images.nix {inherit lib pkgs;}).${vmConfig.rosVersion}
      else
        throw ''
          routnix: vm.rosVersion "${vmConfig.rosVersion}" is RouterOS ${imageMajor}, but device.platform is ${evaluated.config.device.platform} -- set device.platform to routeros_v${imageMajor}, or boot a RouterOS ${platformMajor} image via vm.image
        '';

  vmScript = (import ./mk_vm.nix {inherit pkgs;}) {
    inherit name;
    rscFile = rscFile;
    image = vmImage;
    sshPort = vmConfig.sshPort;
    console = vmConfig.console;
    secretUpload = vmSecretUploader;
  };

  apply = pkgs.writeShellApplication {
    name = "apply";
    runtimeInputs = [openssh];
    text = ''
      usage() {
        echo "Usage: apply [--copy-only | --copy-with-secrets] ${hostArg}"
        echo
        echo "  -c, --copy-only          copy the .rsc without importing it or uploading secrets"
        echo "      --copy-with-secrets  copy the .rsc and upload the secret payload, without importing"
        echo "  -h, --help               show this help"
        echo
        echo "Extra ssh/scp options: ROUTNIX_SSH_OPTS / ROUTNIX_SCP_OPTS env vars"
        if [ -n "$default_host" ]; then
          echo "Default host: $default_host"
        fi
      }

      default_host="${defaultHost}"
      secret_upload=${pkgs.lib.escapeShellArg secretUploaderScript}
      copy_only=false
      copy_with_secrets=false
      host=""

      for arg in "$@"; do
        case "$arg" in
          -c | --copy-only)
            copy_only=true
            ;;
          --copy-with-secrets)
            copy_with_secrets=true
            ;;
          -h | --help)
            usage
            exit 0
            ;;
          -*)
            echo "apply: unknown option: $arg" >&2
            usage >&2
            exit 2
            ;;
          *)
            if [ -n "$host" ]; then
              echo "apply: unexpected extra argument: $arg" >&2
              usage >&2
              exit 2
            fi
            host="$arg"
            ;;
        esac
      done

      if [ -z "$host" ]; then
        host="$default_host"
      fi

      if [ -z "$host" ]; then
        usage >&2
        exit 2
      fi

      ssh_opts=(${pkgs.lib.escapeShellArgs sshOptions})
      scp_opts=(${pkgs.lib.escapeShellArgs scpOptions})

      IFS=' ' read -ra extra_ssh_opts <<< "''${ROUTNIX_SSH_OPTS:-}"
      IFS=' ' read -ra extra_scp_opts <<< "''${ROUTNIX_SCP_OPTS:-}"
      ssh_opts+=("''${extra_ssh_opts[@]}")
      scp_opts+=("''${extra_scp_opts[@]}")

      upload_secrets() {
        if [ -n "$secret_upload" ]; then
          echo "Uploading secrets to $host" >&2
          "$secret_upload" "$host"
        fi
      }

      echo "Copying ${remoteName} to $host" >&2
      scp "''${scp_opts[@]}" "${rscFile}" "$host:${remoteName}"

      if [ "$copy_only" = true ]; then
        exit 0
      fi

      upload_secrets

      if [ "$copy_with_secrets" = true ]; then
        exit 0
      fi

      echo "Importing ${remoteName} on $host" >&2
      ssh "''${ssh_opts[@]}" "$host" "/import ${remoteName}; /file remove ${remoteName}"
    '';
  };
in
  rscFile // {inherit apply; vm = vmScript;}
