#!/usr/bin/env python3
"""Systemd user-service sandbox posture parity with disposable drop-ins."""
import importlib.util
import json
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


def rust(lan, wayvnc):
    result = subprocess.run([str(RUST), "hardening", str(lan), str(wayvnc)],
                            capture_output=True, text=True, check=True, timeout=5)
    assert result.stderr == "", result.stderr
    return json.loads(result.stdout)


def main():
    controller.RUST_HARDENING_BIN = RUST
    with tempfile.TemporaryDirectory(prefix="nyvorel-arch-hardening-") as directory:
        root = Path(directory)
        lan, wayvnc = root / "lan.conf", root / "vnc.conf"
        controller.LAN_SHARE_HARDENING_DROPIN = lan
        controller.WAYVNC_HARDENING_DROPIN = wayvnc
        valid = "[Service]\n" + "\n".join(f"{key}={value}" for key, value in controller.HARDENING_REQUIRED.items()) + "\n"
        for lan_text, vnc_text in (("", ""), (valid, valid),
                                   (valid.replace("NoNewPrivileges=yes", "NoNewPrivileges=no"), valid),
                                   (valid, valid.replace("AF_UNIX AF_INET AF_INET6", "AF_INET AF_UNIX AF_INET6"))):
            lan.write_text(lan_text, encoding="utf-8")
            wayvnc.write_text(vnc_text, encoding="utf-8")
            expected = controller.user_service_hardening_posture()
            assert rust(lan, wayvnc) == expected
            assert controller.snapshot_user_service_hardening_posture() == expected
        bad = root / "bad"
        bad.write_text("#!/bin/sh\necho invalid-json\n", encoding="utf-8")
        bad.chmod(0o755)
        controller.RUST_HARDENING_BIN = bad
        assert controller.snapshot_user_service_hardening_posture() == controller.user_service_hardening_posture()
    print("Arch Remote systemd hardening posture and fallback parity: passed")


if __name__ == "__main__":
    main()
