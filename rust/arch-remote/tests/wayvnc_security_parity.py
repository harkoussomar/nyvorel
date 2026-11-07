#!/usr/bin/env python3
"""WayVNC posture parity with disposable files and a fake systemctl."""
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


def rust(paths):
    result = subprocess.run([str(RUST), "wayvnc-security", *(str(path) for path in paths)],
                            text=True, capture_output=True, check=True, timeout=10)
    assert result.stderr == "", result.stderr
    return json.loads(result.stdout)


def main():
    controller.RUST_WAYVNC_SECURITY_BIN = RUST
    with tempfile.TemporaryDirectory(prefix="nyvorel-arch-wayvnc-") as directory:
        root = Path(directory)
        config, key, cert, launcher, dropin = [root / name for name in
                                        ("arch-remote.conf", "key.pem", "cert.pem", "wayvnc-remote", "security.conf")]
        paths = (config, key, cert, launcher, dropin)
        (controller.WAYVNC_CONFIG, controller.WAYVNC_TLS_KEY, controller.WAYVNC_TLS_CERT,
         controller.WAYVNC_LAUNCHER, controller.WAYVNC_SECURITY_DROPIN) = paths
        fake_systemctl = root / "systemctl"
        fake_systemctl.write_text("#!/bin/sh\nprintf '%s\\n' 'ExecStart={ path=/home/user/.local/bin/wayvnc-remote }'\n",
                                   encoding="utf-8")
        fake_systemctl.chmod(0o755)
        old_path = os.environ.get("PATH", "")
        os.environ["PATH"] = f"{root}:{old_path}"
        try:
            def check():
                expected = controller.wayvnc_security_posture()
                actual = rust(paths)
                assert actual == expected, (actual, expected)
                assert controller.snapshot_wayvnc_security_posture() == expected
                assert "very-secret" not in json.dumps(actual)
                return actual

            assert check()["ok"] is False
            config.write_text(f"enable_auth=true\nusername=remote\npassword=very-secret-password-123\n"
                              f"private_key_file={key}\ncertificate_file={cert}\n", encoding="utf-8")
            config.chmod(0o600)
            key.write_text("private key", encoding="utf-8")
            key.chmod(0o600)
            cert.write_text("certificate", encoding="utf-8")
            launcher.write_text("#!/bin/sh\ntailscale ip -4\nwayvnc --config arch-remote.conf\n", encoding="utf-8")
            launcher.chmod(0o755)
            dropin.write_text("[Service]\nExecStart=%h/.local/bin/wayvnc-remote\n", encoding="utf-8")
            assert check()["ok"] is True
            launcher.write_text("#!/bin/sh\ntailscale ip -4\nwayvnc --config arch-remote.conf 100.101.102.103:5900\n",
                                encoding="utf-8")
            assert check()["dynamic_tailnet_bind"] is False
            launcher.write_text("#!/bin/sh\ntailscale ip -4\nwayvnc --config arch-remote.conf\n", encoding="utf-8")
            config.chmod(0o644)
            assert check()["ok"] is False
            bad = root / "invalid-rust"
            bad.write_text("#!/bin/sh\necho invalid-json\n", encoding="utf-8")
            bad.chmod(0o755)
            controller.RUST_WAYVNC_SECURITY_BIN = bad
            assert controller.snapshot_wayvnc_security_posture() == controller.wayvnc_security_posture()
        finally:
            os.environ["PATH"] = old_path
    print("Arch Remote WayVNC security and fallback parity: passed")


if __name__ == "__main__":
    main()
