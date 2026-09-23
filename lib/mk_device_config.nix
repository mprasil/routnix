{evalConfig}:
# Evaluates a router's `modules` (via `evalConfig`) and packages the
# rendered `.rsc` as a derivation, with a thin `apply` wrapper attached
# via `passthru`:
#
#   mkDeviceConfig { inherit pkgs; name = "home-router"; modules = [ ./home-router.nix ]; }
#
# `apply` scps the `.rsc` to `<user@host>` (a runtime argument, not baked
# into the package) and runs `/import` over ssh, removing the file from
# the router afterwards; `--copy-only` stops after the copy. Auth, host
# keys, and identity are left entirely to the caller's own ssh/scp
# config and agent; `ROUTNIX_SSH_OPTS`/`ROUTNIX_SCP_OPTS` pass extra
# space-separated options straight through to `ssh`/`scp` (e.g. a
# non-default port or identity file) for cases not already covered by
# `~/.ssh/config`.
{
  pkgs,
  modules,
  name ? "routnix",
}: let
  evaluated = evalConfig {inherit modules;};
  remoteName = "${name}.rsc";
  rscFile = pkgs.writeText remoteName evaluated.rsc;

  apply = pkgs.writeShellApplication {
    name = "apply";
    runtimeInputs = [pkgs.openssh];
    # SC2029: $remote_name is meant to expand client-side -- it's a fixed
    # value substituted by Nix, not something the router's shell needs to
    # resolve.
    excludeShellChecks = ["SC2029"];
    text = ''
      usage() {
        echo "Usage: apply <user@host> [--copy-only]" >&2
        echo "Extra ssh/scp options: ROUTNIX_SSH_OPTS / ROUTNIX_SCP_OPTS env vars" >&2
        exit 1
      }

      [ "$#" -ge 1 ] || usage

      host="$1"
      shift

      copy_only=false
      if [ "$#" -gt 0 ]; then
        [ "$1" = "--copy-only" ] || usage
        copy_only=true
        shift
      fi

      [ "$#" -eq 0 ] || usage

      remote_name="${remoteName}"

      IFS=' ' read -ra ssh_opts <<< "''${ROUTNIX_SSH_OPTS:-}"
      IFS=' ' read -ra scp_opts <<< "''${ROUTNIX_SCP_OPTS:-}"

      scp "''${scp_opts[@]}" "${rscFile}" "$host:$remote_name"

      if ! "$copy_only"; then
        ssh "''${ssh_opts[@]}" "$host" "/import $remote_name"
        ssh "''${ssh_opts[@]}" "$host" "/file remove $remote_name"
      fi
    '';
  };
in
  rscFile // {inherit apply;}
