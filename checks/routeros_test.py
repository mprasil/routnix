#!/usr/bin/env python3
"""Integration test: apply a routnix-generated .rsc to a RouterOS CHR VM and
verify the expected configuration is present.

Exit codes: 0 = pass, non-zero = fail.

"""

from __future__ import annotations

import argparse
import shutil
import sys
import tempfile
from pathlib import Path

from routeros_machine import RouterOsMachine
from test_driver.logger import TerminalLogger


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--image",    required=True, help="Path to the CHR .img file")
    p.add_argument("--rsc",      required=True, help="Path to the .rsc file to apply")
    p.add_argument("--qemu",     required=True, help="Path to qemu-system-x86_64")
    p.add_argument("--ssh",      required=True, help="Path to ssh binary")
    p.add_argument("--scp",      required=True, help="Path to scp binary")
    p.add_argument("--ssh-port", type=int, default=2222,
                   help="Host TCP port forwarded to RouterOS SSH")
    p.add_argument("--out-dir",  required=True,
                   help="Directory for test artefacts")
    return p.parse_args()


def assert_contains(output: str, *needles: str, context: str = "") -> None:
    """Assert every needle appears in *output*; raise on the first miss."""
    for needle in needles:
        if needle not in output:
            raise AssertionError(
                f"Expected {needle!r} in output"
                + (f" ({context})" if context else "")
                + f"\nActual output:\n{output}"
            )


def main() -> None:
    args = parse_args()

    with tempfile.TemporaryDirectory() as _tmp:
        tmp_dir = Path(_tmp)
        out_dir = Path(args.out_dir)
        out_dir.mkdir(parents=True, exist_ok=True)

        ros = RouterOsMachine(
            qemu_bin=args.qemu,
            image_path=args.image,
            name="routeros",
            ssh_port=args.ssh_port,
            ssh_bin=args.ssh,
            scp_bin=args.scp,
            tmp_dir=tmp_dir,
            out_dir=out_dir,
            logger=TerminalLogger(),
        )

        failure: Exception | None = None
        try:
            _run_test(ros, args)
        except Exception as exc:
            failure = exc
        finally:
            # release() before reading the console log, so the serial
            # thread has been joined and the log is fully populated.
            ros.release()

        if failure is not None:
            print("\n=== RouterOS console log ===", file=sys.stderr)
            print(ros.get_console_log(), file=sys.stderr)
            print("=== end console log ===\n", file=sys.stderr)
            raise SystemExit(f"FAIL: {failure}") from failure

        # Only reached on success. Leave the console log and applied .rsc
        # behind so a passing build has something inspectable.
        (out_dir / "console.log").write_text(ros.get_console_log())
        shutil.copy(args.rsc, out_dir / "routnix-test.rsc")


def _run_test(ros: RouterOsMachine, args: argparse.Namespace) -> None:
    log = ros.logger

    with log.nested("boot RouterOS CHR"):
        ros.start()

    with log.nested("wait for SSH"):
        ros.wait_for_ssh()

    # Upload the .rsc file ----------------------------------------------
    rsc_remote = "routnix-test.rsc"
    with log.nested(f"upload {args.rsc}"):
        ros.scp_to_ros(args.rsc, rsc_remote)

    # Import the .rsc ----------------------------------------------------
    with log.nested("import .rsc"):
        import_out = ros.ssh_cmd(f"/import {rsc_remote}", timeout=60)
        print(f"import output: {import_out}")

    # Verify firewall filter rules ---------------------------------------
    with log.nested("verify /ip/firewall/filter"):
        filter_out = ros.ssh_cmd("/ip/firewall/filter/print")
        assert_contains(
            filter_out,
            "allow-icmp",
            "allow-established",
            "allow-ssh-trusted",
            "drop-rest",
            context="/ip/firewall/filter/print",
        )

    # Verify address-list entries ----------------------------------------
    with log.nested("verify /ip/firewall/address-list"):
        alist_out = ros.ssh_cmd("/ip/firewall/address-list/print")
        assert_contains(
            alist_out,
            "trusted-ips",
            "192.168.1.0/24",
            context="/ip/firewall/address-list/print",
        )

    print("PASS: all assertions satisfied")


if __name__ == "__main__":
    main()
