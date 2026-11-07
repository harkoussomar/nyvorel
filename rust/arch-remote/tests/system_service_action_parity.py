#!/usr/bin/env python3
"""Privileged Tailscale command parity using a fake pkexec, never real polkit."""
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


def main():
    with tempfile.TemporaryDirectory(prefix="nyvorel-system-service-") as directory:
        folder = Path(directory)
        pkexec = folder / "fake-pkexec"
        systemctl = folder / "fake-systemctl"
        marker = folder / "called"
        systemctl.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        pkexec.write_text("#!/usr/bin/env python3\nimport os,sys\n"
                          "assert sys.argv[1] == os.environ['FAKE_SYSTEMCTL']\n"
                          "assert sys.argv[2:] in (['start','tailscaled'], ['restart','tailscaled'])\n"
                          "open(os.environ['FAKE_MARKER'],'w').write(sys.argv[2])\n"
                          "if os.environ.get('FAKE_FAIL') == '1':\n"
                          "    print('synthetic-denied',file=sys.stderr); sys.exit(1)\n", encoding="utf-8")
        pkexec.chmod(0o700)
        systemctl.chmod(0o700)
        os.environ.update(FAKE_SYSTEMCTL=str(systemctl), FAKE_MARKER=str(marker))
        controller.exe = lambda name: str(pkexec) if name == "pkexec" else str(systemctl) if name == "systemctl" else None
        controller.snapshot = lambda force=False: {"services": {"tailscaled": {
            "ready": marker.exists(), "readiness_reason": "Ready"}}}
        controller.record_activity = lambda *args: None
        controller.time.sleep = lambda seconds: None
        count = 0
        for action, fail in (("start", False), ("restart", False), ("start", True)):
            marker.unlink(missing_ok=True)
            os.environ["FAKE_FAIL"] = "1" if fail else "0"
            controller.RUST_SYSTEM_SERVICE_ACTION_BIN = RUST
            actual = controller.system_service_action("tailscaled", action)
            marker.unlink(missing_ok=True)
            controller.RUST_SYSTEM_SERVICE_ACTION_BIN = folder / "missing"
            expected = controller.system_service_action("tailscaled", action)
            assert actual == expected, (actual, expected)
            count += 1
        os.environ.pop("FAKE_FAIL", None)
        inputs = {"name": "sshd", "action": "stop", "pkexec": str(pkexec), "systemctl": str(systemctl)}
        result = subprocess.run([str(RUST), "system-service-action"], input=json.dumps(inputs),
                                text=True, capture_output=True, check=True)
        assert json.loads(result.stdout)["ok"] is False
        bad = folder / "bad-rust"
        bad.write_text("#!/bin/sh\necho invalid-json\n", encoding="utf-8")
        bad.chmod(0o700)
        controller.RUST_SYSTEM_SERVICE_ACTION_BIN = bad
        marker.unlink(missing_ok=True)
        assert "backend returned invalid state" in controller.system_service_action("tailscaled", "start")["message"]
        assert not marker.exists()
    print(f"Arch Remote Tailscale service action and fallback parity: {count} cases passed")


if __name__ == "__main__":
    main()
