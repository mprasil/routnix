{evalConfig}:
# Evaluates a router's `modules` (via `evalConfig`) and packages the
# rendered `.rsc` as a derivation, with a thin `apply` wrapper attached
# via `passthru`:
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
{
  pkgs,
  modules,
  name ? "routnix",
  host ? null,
  openssh ? pkgs.openssh,
  sshOptions ? [],
  scpOptions ? [],
}: let
  evaluated = evalConfig {inherit modules;};
  rscFile = pkgs.writeText "${name}.rsc" evaluated.rsc;
  remoteName = builtins.baseNameOf rscFile;
  defaultHost = if host == null then "" else host;
  hostArg = if host == null then "<user@host>" else "[<user@host>]";

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
  rscFile // {inherit apply;}
