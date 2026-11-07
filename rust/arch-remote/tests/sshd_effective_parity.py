#!/usr/bin/env python3
"""Contextual sshd -T proof parity, including failure and privileged paths."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[3]
PYTHON = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else ROOT / "quickshell/scripts/arch-remote/control_center.py"
RUST = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "target/release/nyvorel-arch-remote"
spec = importlib.util.spec_from_file_location("arch_remote", PYTHON)
controller = importlib.util.module_from_spec(spec)
spec.loader.exec_module(controller)


def main():
    with tempfile.TemporaryDirectory(prefix="nyvorel-arch-sshd-") as directory:
        root = Path(directory)
        sshd = root / "sshd"
        sshd.write_text('#!/bin/sh\n/bin/cat "$ARCH_REMOTE_SSHD_OUTPUT"\n'
                        'if [ "$ARCH_REMOTE_SSHD_FAIL" = 1 ]; then echo "$ARCH_REMOTE_SSHD_ERROR" >&2; exit 1; fi\n', encoding="utf-8")
        sshd.chmod(0o755)
        pkexec = root / "pkexec"
        pkexec.write_text('#!/bin/sh\nexec "$@"\n', encoding="utf-8")
        pkexec.chmod(0o755)
        output = root / "output"
        os.environ["ARCH_REMOTE_SSHD_OUTPUT"] = str(output)
        controller.RUST_SSHD_EFFECTIVE_BIN = RUST
        real_path = controller.Path

        class MissingSystemSshd:
            def is_file(self):
                return False

        controller.Path = lambda value: MissingSystemSshd() if str(value) == "/usr/bin/sshd" else real_path(value)
        controller.exe = lambda name: str(sshd) if name == "sshd" else str(pkexec) if name == "pkexec" else None
        cases = [
            ("permitrootlogin no\npubkeyauthentication yes\npasswordauthentication no\nkbdinteractiveauthentication no\nallowusers test\n", False, ""),
            ("permitrootlogin no\npasswordauthentication no\n", False, ""),
            ("", True, "sshd: no hostkeys available -- exiting."),
            ("", True, "generic sshd failure"),
        ]
        try:
            for text, fail, error in cases:
                output.write_text(text, encoding="utf-8")
                os.environ["ARCH_REMOTE_SSHD_FAIL"] = "1" if fail else "0"
                os.environ["ARCH_REMOTE_SSHD_ERROR"] = error
                for privileged in (False, True):
                    expected = controller.run_sshd_effective(privileged)
                    command = [str(RUST), "sshd-effective", str(sshd), str(pkexec), controller.USER,
                               "1" if privileged else "0"]
                    result = subprocess.run(command, capture_output=True, text=True, check=True, timeout=22)
                    assert json.loads(result.stdout) == expected
                    assert controller.snapshot_sshd_effective(privileged) == expected
            bad = root / "bad"
            bad.write_text("#!/bin/sh\necho invalid-json\n", encoding="utf-8")
            bad.chmod(0o755)
            controller.RUST_SSHD_EFFECTIVE_BIN = bad
            assert controller.snapshot_sshd_effective(False) == controller.run_sshd_effective(False)
        finally:
            for key in ("ARCH_REMOTE_SSHD_OUTPUT", "ARCH_REMOTE_SSHD_FAIL", "ARCH_REMOTE_SSHD_ERROR"):
                os.environ.pop(key, None)
    print("Arch Remote contextual SSH policy proof and fallback parity: passed")


if __name__ == "__main__":
    main()
