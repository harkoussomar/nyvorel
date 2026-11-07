#!/usr/bin/env python3
"""Pairing cancellation parity using a fake LAN Share executable only."""
import importlib.util
import os
import shlex
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[3]
RUST = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "target/release/nyvorel-arch-remote"
PYTHON = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else ROOT / "quickshell/scripts/arch-remote/control_center.py"
spec = importlib.util.spec_from_file_location("arch_remote", PYTHON)
controller = importlib.util.module_from_spec(spec)
spec.loader.exec_module(controller)


def main():
    with tempfile.TemporaryDirectory(prefix="nyvorel-pair-cancel-") as directory:
        folder = Path(directory)
        fake = folder / "fake-lan-share"
        fake.write_text("#!/usr/bin/env python3\nimport os,sys\n"
                        "assert sys.argv[1:] == ['pair','--cancel','--json']\n"
                        "print('synthetic response')\n"
                        "sys.exit(int(os.environ.get('CANCEL_EXIT','0')))\n", encoding="utf-8")
        fake.chmod(0o700)
        rust_model = folder / "rust-pairing-cancel-model"
        rust_model.write_text(f"#!/bin/sh\nshift\nexec {shlex.quote(str(RUST))} pairing-cancel-model \"$@\"\n")
        rust_model.chmod(0o700)
        support = {"binary": str(fake), "cancel_supported": True}
        controller.snapshot_pair_command_support = lambda: support
        controller.record_activity = lambda *args: None
        count = 0
        for installed, supported, exit_code in ((True, True, 0), (True, True, 1),
                                                (True, False, 0), (False, False, 0)):
            support = {"binary": str(fake) if installed else "", "cancel_supported": supported}
            os.environ["CANCEL_EXIT"] = str(exit_code)
            controller.RUST_PAIRING_CANCEL_BIN = rust_model
            actual = controller.pairing_cancel()
            controller.RUST_PAIRING_CANCEL_BIN = folder / "missing"
            expected = controller.pairing_cancel()
            assert actual == expected, (actual, expected)
            count += 1
        bad = folder / "invalid-rust"
        bad.write_text("#!/bin/sh\necho invalid-json\n", encoding="utf-8")
        bad.chmod(0o700)
        controller.RUST_PAIRING_CANCEL_BIN = bad
        assert "backend failed" in controller.pairing_cancel()["message"]
        os.environ.pop("CANCEL_EXIT", None)
    print(f"Arch Remote pairing cancel and fallback parity: {count} cases passed")


if __name__ == "__main__":
    main()
