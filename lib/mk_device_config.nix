{evalConfig}:
# Evaluates a router's `modules` (via `evalConfig`) and packages the
# rendered `.rsc` as a derivation, with an `apply` and a `vm` wrapper
# attached via `passthru`:
#
#   mkDeviceConfig { inherit pkgs; name = "home-router"; modules = [ ./home-router.nix ]; }
#
# `apply` scps the `.rsc` to `<user@host>` (a runtime argument, defaulting
# to `host` when one is set) and runs `/import` over ssh, removing the file
# from the router afterwards; `--copy-only` stops after the copy. Auth,
# host keys, and identity are left entirely to the caller's own ssh/scp
# config and agent; `sshOptions`/`scpOptions` (and the
# `ROUTNIX_SSH_OPTS`/`ROUTNIX_SCP_OPTS` env vars) pass extra options
# through to `ssh`/`scp` (e.g. a non-default port or identity file). The
# uploaded file is named after the `.rsc` store path (`<hash>-<name>.rsc`).
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
  vm ? {},
}: let
  inherit (pkgs) lib;

  evaluated = evalConfig {inherit modules;};
  rscFile = pkgs.writeText "${name}.rsc" evaluated.rsc;
  remoteName = builtins.baseNameOf rscFile;
  defaultHost = if host == null then "" else host;
  hostArg = if host == null then "<user@host>" else "[<user@host>]";

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
  };

  apply = pkgs.writeShellApplication {
    name = "apply";
    runtimeInputs = [openssh];
    text = ''
      usage() {
        echo "Usage: apply [--copy-only] ${hostArg}"
        echo
        echo "  -c, --copy-only   copy the .rsc to the router without importing it"
        echo "  -h, --help        show this help"
        echo
        echo "Extra ssh/scp options: ROUTNIX_SSH_OPTS / ROUTNIX_SCP_OPTS env vars"
        if [ -n "$default_host" ]; then
          echo "Default host: $default_host"
        fi
      }

      default_host="${defaultHost}"
      copy_only=false
      host=""

      for arg in "$@"; do
        case "$arg" in
          -c | --copy-only)
            copy_only=true
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

      echo "Copying ${remoteName} to $host" >&2
      scp "''${scp_opts[@]}" "${rscFile}" "$host:${remoteName}"

      if [ "$copy_only" = false ]; then
        echo "Importing ${remoteName} on $host" >&2
        ssh "''${ssh_opts[@]}" "$host" "/import ${remoteName}"

        echo "Removing ${remoteName} from $host" >&2
        ssh "''${ssh_opts[@]}" "$host" "/file remove ${remoteName}"
      fi
    '';
  };
in
  rscFile // {inherit apply; vm = vmScript;}
