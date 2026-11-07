#!/usr/bin/env python3
"""Pairing capability parity; assert no credential-minting command is invoked."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[3]
RUST = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "target/release/nyvorel-arch-remote"
PYTHON = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else ROOT / "quickshell/scripts/arch-remote/control_center.py"
spec = importlib.util.spec_from_file_location("arch_remote", PYTHON)
controller = importlib.util.module_from_spec(spec)
spec.loader.exec_module(controller)


def rust(binary):
    result = subprocess.run([str(RUST), "pair-support", str(binary or "")],
                            text=True, capture_output=True, check=True, timeout=10)
    assert result.stderr == "", result.stderr
    return json.loads(result.stdout)


def main():
    controller.RUST_PAIR_SUPPORT_BIN = RUST
    with tempfile.TemporaryDirectory(prefix="nyvorel-arch-pair-support-") as directory:
        root = Path(directory)
        binary = root / "lan-share"
        calls = root / "calls"
        selected = None
        controller.resolve_lan_share_binary = lambda: selected
        old = os.environ.get("PAIR_TEST_CALLS")
        os.environ["PAIR_TEST_CALLS"] = str(calls)
        try:
            def check():
                expected = controller.pair_command_support()
                assert rust(selected) == expected
                assert controller.snapshot_pair_command_support() == expected
                if calls.exists():
                    assert all(line in {"pair --help", "--help"} for line in calls.read_text().splitlines())
                return expected

            assert check()["status"] == "missing"
            selected = str(binary)
            for pair_exit, pair_text, top_exit, top_text, expected_status in (
                (0, "pair --json --cancel", 1, "", "supported"),
                (1, "pair subcommand", 1, "", "supported"),
                (1, "unknown", 0, "commands: pair, status", "supported"),
                (1, "unknown", 0, "commands: status", "unsupported"),
            ):
                script = ("#!/bin/sh\n"
                          "printf '%s\\n' \"$*\" >> \"$PAIR_TEST_CALLS\"\n"
                          f"if [ \"$1\" = pair ]; then printf '%s\\n' '{pair_text}'; exit {pair_exit}; fi\n"
                          f"printf '%s\\n' '{top_text}'; exit {top_exit}\n")
                binary.write_text(script, encoding="utf-8")
                binary.chmod(0o755)
                assert check()["status"] == expected_status
            invalid = root / "invalid-rust"
            invalid.write_text("#!/bin/sh\necho invalid-json\n", encoding="utf-8")
            invalid.chmod(0o755)
            controller.RUST_PAIR_SUPPORT_BIN = invalid
            assert controller.snapshot_pair_command_support() == controller.pair_command_support()
        finally:
            if old is None:
                os.environ.pop("PAIR_TEST_CALLS", None)
            else:
                os.environ["PAIR_TEST_CALLS"] = old
    print("Arch Remote pairing capability and fallback parity: passed")


if __name__ == "__main__":
    main()
