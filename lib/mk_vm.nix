{pkgs}: {
  name,
  rscFile,
  image,
  sshPort ? 2222,
  console ? false,
}: let
  inherit (pkgs) lib;

  qemu = "${pkgs.qemu}/bin/qemu-system-x86_64";
  remoteName = builtins.baseNameOf rscFile;
in
  pkgs.writeShellApplication {
    name = "vm-${name}";
    runtimeInputs = [pkgs.openssh pkgs.coreutils];
    text = ''
      qemu=${lib.escapeShellArg qemu}
      rsc_file=${lib.escapeShellArg (toString rscFile)}
      remote_name=${lib.escapeShellArg remoteName}
      default_port=${toString sshPort}

      msg() { printf '%s\r\n' "$*" >&2; }

      usage() {
        echo "Usage: vm-${name} [--console]"
        echo
        echo "Boots a RouterOS CHR VM, applies ${name}'s configuration to it over SSH,"
        echo "then stays in the foreground until the VM is stopped."
        echo
        echo "  --console   attach the guest console to this terminal instead of"
        echo "              logging it to a file; the VM is then stopped with the"
        echo "              QEMU monitor escape ctrl-A x rather than Ctrl-C"
        echo "  -h, --help  show this help"
        echo
        echo "Environment:"
        echo "  VM_SSH_PORT   host port forwarded to the VM's SSH (default $default_port)"
      }

      port="''${VM_SSH_PORT:-$default_port}"
      attach_console=${lib.boolToString console}

      while [ $# -gt 0 ]; do
        case "$1" in
          --console) attach_console=true ;;
          -h | --help)
            usage
            exit 0
            ;;
          *)
            msg "vm-${name}: unknown argument: $1"
            usage >&2
            exit 2
            ;;
        esac
        shift
      done

      image_file="$(ls ${image}/*.img)"

      # A freshly booted VM has an unknown host key and offers no key-based
      # auth; RouterOS accepts the default admin account's empty password
      # through the "none" auth method.
      ssh_opts=(
        -F none
        -o StrictHostKeyChecking=no
        -o UserKnownHostsFile=/dev/null
        -o PubkeyAuthentication=no
        -o BatchMode=yes
        -p "$port"
      )
      scp_opts=(
        -F none
        -o StrictHostKeyChecking=no
        -o UserKnownHostsFile=/dev/null
        -o PubkeyAuthentication=no
        -o BatchMode=yes
        -P "$port"
      )

      # RouterOS re-parses these commands itself, so expanding them on this
      # side is intended rather than a quoting mistake.
      # shellcheck disable=SC2029
      ros_ssh() { ssh "''${ssh_opts[@]}" admin@127.0.0.1 "$@"; }

      wait_for_ssh() {
        local deadline=$((SECONDS + 120))
        until ros_ssh "/system identity print" >/dev/null 2>&1; do
          if [ "$SECONDS" -ge "$deadline" ]; then
            msg "vm-${name}: RouterOS did not answer on 127.0.0.1:$port within 120s"
            return 1
          fi
          sleep 1
        done
      }

      apply_config() {
        wait_for_ssh || return 1

        msg "vm-${name}: copying $remote_name to the VM"
        scp "''${scp_opts[@]}" "$rsc_file" "admin@127.0.0.1:$remote_name"

        msg "vm-${name}: importing $remote_name"
        ros_ssh "/import $remote_name; /file remove $remote_name" || true

        if ros_ssh "/system identity print" >/dev/null 2>&1; then
          msg "vm-${name}: configuration applied"
        else
          msg "vm-${name}: warning: the VM stopped answering over SSH after applying"
          msg "vm-${name}: a declared /user or firewall change may have cut it off"
        fi
      }

      console_log=""
      if [ "$attach_console" = true ]; then
        display_args=(-nographic -serial mon:stdio)
      else
        console_log="$(mktemp "''${TMPDIR:-/tmp}/routnix-vm-${name}.XXXXXX")"
        display_args=(-display none -serial "file:$console_log")
      fi

      msg "vm-${name}: booting RouterOS CHR from $image_file"
      msg "vm-${name}: ssh -p $port admin@127.0.0.1"
      if [ "$attach_console" = true ]; then
        msg "vm-${name}: console attached; stop the VM with ctrl-A x"
      else
        msg "vm-${name}: console log: $console_log"
        msg "vm-${name}: stop the VM with Ctrl-C"
      fi

      applier_pid=""
      cleanup() {
        status=$?
        if [ -n "$applier_pid" ]; then
          kill "$applier_pid" 2>/dev/null || true
          wait "$applier_pid" 2>/dev/null || true
        fi
        if [ -n "$console_log" ]; then
          msg "vm-${name}: console log kept at $console_log"
        fi
        exit "$status"
      }
      trap cleanup EXIT

      apply_config &
      applier_pid=$!

      "$qemu" \
        -m 256 \
        -machine type=pc,accel=kvm:tcg \
        -drive "file=$image_file,format=raw,if=virtio,id=hd0,snapshot=on" \
        -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:$port-:22" \
        -device virtio-net-pci,netdev=net0 \
        "''${display_args[@]}"
    '';
  }
