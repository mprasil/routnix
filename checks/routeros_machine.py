"""RouterOsMachine — thin wrapper around nixpkgs' QemuMachine for RouterOS CHR.

RouterOS-specific operations (SSH commands, SCP file transfer) are implemented
here on top of that foundation.

RouterOS accepts non-interactive SSH commands on the default `admin` account
with its empty password, so no setup step is needed before using it.

"""

from __future__ import annotations

import subprocess
import time
from pathlib import Path

from test_driver.logger import AbstractLogger
from test_driver.machine import QemuMachine, QemuStartCommand


class RouterOsStartCommand(QemuStartCommand):
    """QemuStartCommand variant that omits virtconsole and sets some reasonable
    defaults for starting RouterOS machine.
    """

    def cmd(
        self,
        monitor_socket_path: Path,
        qmp_socket_path: Path,
        shell_socket_path: Path,
        allow_reboot: bool = False,
        vsock_guest: Path | None = None,
    ) -> str:
        qemu_opts = (
            " -device virtio-rng-pci"
            " -serial stdio"
        )
        if not allow_reboot:
            qemu_opts += " -no-reboot"

        return (
            f"{self._cmd}"
            f" -qmp unix:{qmp_socket_path},server=on,wait=off"
            f" -monitor unix:{monitor_socket_path}"
            # Keep the chardev so accept_or_fail() succeeds; RouterOS has no
            # device attached to it so it never writes there.
            f" -chardev socket,id=shell,path={shell_socket_path}"
            f"{qemu_opts}"
            f" -nographic"
        )


class RouterOsMachine(QemuMachine):
    """A running RouterOS CHR instance managed via QEMU."""

    ssh_bin: str
    scp_bin: str
    ssh_port: int

    def __init__(
        self,
        qemu_bin: str,
        image_path: str,
        name: str,
        ssh_port: int,
        ssh_bin: str,
        scp_bin: str,
        tmp_dir: Path,
        out_dir: Path,
        logger: AbstractLogger,
    ) -> None:
        super().__init__(
            out_dir=out_dir,
            tmp_dir=tmp_dir,
            start_command="fake-qemu", # We're replacing this bellow
            logger=logger,
            name=name,
        )

        self.ssh_bin = ssh_bin
        self.scp_bin = scp_bin
        self.ssh_port = ssh_port

        start_command = (
            f"{qemu_bin}"
            f" -enable-kvm"
            f" -m 256"
            # RouterOS CHR is MBR-partitioned and expects legacy boot.
            f" -machine type=pc"
            f" -drive file={image_path},format=raw,if=virtio,id=hd0"
            # Redirects guest writes to a temp file as image is read-only:
            f",snapshot=on"
            f" -netdev user,id=net0,hostfwd=tcp:127.0.0.1:{ssh_port}-:22"
            f" -device virtio-net-pci,netdev=net0"
        )
        self.start_command = RouterOsStartCommand(start_command)

    # SSH / SCP from the host
    # ------------------------------------------------------------------

    def wait_for_ssh(self, timeout: int = 120) -> None:
        """Poll until RouterOS SSH is fully ready to accept commands.

        A plain TCP connect is not enough — RouterOS opens the port before its
        SSH daemon is ready to complete the banner exchange. Instead we attempt
        an inert SSH command and retry until it succeeds or the timeout expires.
        """
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            proc = subprocess.run(
                [
                    *self._ssh_base(connect_timeout=5),
                    "/system/identity/print",
                ],
                capture_output=True,
                timeout=30,
            )
            if proc.returncode == 0:
                return
            time.sleep(1)

        raise RuntimeError(
            f"SSH did not become available on localhost:{self.ssh_port} "
            f"within {timeout}s\n"
            f"--- console log ---\n{self.get_console_log()}"
        )

    # Flags shared by every ssh/scp invocation against the RouterOS guest:
    # ignore any ambient ssh config, skip host-key checking (fresh VM each run),
    # and never prompt. The guest's admin account has an empty password, which
    # RouterOS accepts via the "none" auth method, so no password or key is
    # offered at all.
    SSH_HOST_OPTS = [
        "-F", "none",
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "PubkeyAuthentication=no",
        "-o", "BatchMode=yes",
    ]

    def _ssh_base(
        self,
        *,
        connect_timeout: int = 10,
    ) -> list[str]:
        return [
            self.ssh_bin,
            *self.SSH_HOST_OPTS,
            "-o", f"ConnectTimeout={connect_timeout}",
            "-p", str(self.ssh_port),
            "admin@127.0.0.1",
        ]

    def ssh_cmd(self, command: str, *, timeout: int = 60) -> str:
        """Run a single RouterOS CLI *command* via SSH, return stdout.

        Raises ``RuntimeError`` on non-zero exit, including the console log.
        """
        proc = subprocess.run(
            [*self._ssh_base(), command],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        if proc.returncode != 0:
            raise RuntimeError(
                f"SSH command failed (exit {proc.returncode}): {command!r}\n"
                f"stdout: {proc.stdout}\nstderr: {proc.stderr}\n"
                f"--- console log ---\n{self.get_console_log()}"
            )
        return proc.stdout

    def scp_to_ros(
        self,
        local_path: str | Path,
        remote_name: str,
        *,
        timeout: int = 30,
    ) -> None:
        """Copy *local_path* to the RouterOS filesystem root as *remote_name*.

        Raises ``RuntimeError`` on failure, including the console log.
        """
        proc = subprocess.run(
            [
                self.scp_bin,
                *self.SSH_HOST_OPTS,
                "-P", str(self.ssh_port),
                str(local_path),
                f"admin@127.0.0.1:{remote_name}",
            ],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        if proc.returncode != 0:
            raise RuntimeError(
                f"SCP failed (exit {proc.returncode}): "
                f"{local_path} -> {remote_name}\n"
                f"stdout: {proc.stdout}\nstderr: {proc.stderr}\n"
                f"--- console log ---\n{self.get_console_log()}"
            )
