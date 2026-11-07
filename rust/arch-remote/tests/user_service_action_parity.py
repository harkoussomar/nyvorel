#!/usr/bin/env python3
"""User-service action parity with a fake systemctl; never touches systemd."""
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
    with tempfile.TemporaryDirectory(prefix="nyvorel-service-action-") as directory:
        folder = Path(directory)
        fake = folder / "systemctl"
        state_file = folder / "active-state"
        fake.write_text("#!/usr/bin/env python3\nimport os,sys\n"
                        "args=sys.argv[1:]\npath=os.environ['FAKE_ACTIVE_STATE']\n"
                        "if args[:2] == ['--user','show']:\n"
                        "    state=open(path).read().strip()\n"
                        "    print('LoadState=loaded\\nActiveState='+state+'\\nSubState=running\\nUnitFileState=disabled\\nMainPID=123')\n"
                        "elif len(args)==3 and args[0]=='--user':\n"
                        "    if os.environ.get('FAKE_ACTION_FAIL') == '1':\n"
                        "        print('synthetic-denied',file=sys.stderr); sys.exit(1)\n"
                        "    open(path,'w').write('inactive' if args[1]=='stop' else 'active')\n"
                        "else: sys.exit(2)\n", encoding="utf-8")
        fake.chmod(0o700)
        os.environ["FAKE_ACTIVE_STATE"] = str(state_file)
        controller.exe = lambda name: str(fake) if name == "systemctl" else None
        controller.record_activity = lambda *args: None
        controller.time.sleep = lambda seconds: None

        def snapshot(_force=False):
            active = state_file.read_text().strip() == "active"
            return {"graphical": {"hyprland_available": True, "wayland_display": "wayland-1"},
                    "tailscale": {"connected": True},
                    "wayvnc_security": {"ok": True, "reason": "verified"},
                    "services": {"lan_share": {"ready": active, "running": active,
                                               "listeners": [{"address": "127.0.0.1"}] if active else [],
                                               "readiness_reason": "Ready", "bind": "none"},
                                 "wayvnc": {"ready": active, "running": active,
                                            "listeners": [{"address": "100.1.2.3"}] if active else [],
                                            "readiness_reason": "Ready", "bind": "none"}}}
        controller.snapshot = snapshot
        count = 0
        for name, action, initially_active, fail in (
                ("lan-share", "start", False, False), ("lan-share", "stop", True, False),
                ("lan-share", "restart", True, False), ("wayvnc-remote", "start", False, False),
                ("wayvnc-remote", "stop", True, False), ("lan-share", "start", False, True)):
            state_file.write_text("active" if initially_active else "inactive", encoding="utf-8")
            os.environ["FAKE_ACTION_FAIL"] = "1" if fail else "0"
            controller.RUST_USER_SERVICE_ACTION_BIN = RUST
            actual = controller.service_action(name, action)
            state_file.write_text("active" if initially_active else "inactive", encoding="utf-8")
            controller.RUST_USER_SERVICE_ACTION_BIN = folder / "missing"
            expected = controller.service_action(name, action)
            assert actual == expected, (name, action, actual, expected)
            count += 1
        os.environ.pop("FAKE_ACTION_FAIL", None)
        inputs = {"name": "wayvnc-remote", "action": "start", "systemctl": str(fake),
                  "hyprland_available": False, "wayland_display": "", "tailscale_connected": True,
                  "vnc_security_ok": True}
        result = subprocess.run([str(RUST), "user-service-action"], input=json.dumps(inputs),
                                text=True, capture_output=True, check=True)
        assert json.loads(result.stdout)["message"] == "No active Wayland/Hyprland session was detected."
        inputs["name"] = "untrusted.service"
        result = subprocess.run([str(RUST), "user-service-action"], input=json.dumps(inputs),
                                text=True, capture_output=True, check=True)
        assert json.loads(result.stdout)["ok"] is False
        bad = folder / "invalid-rust"
        bad.write_text("#!/bin/sh\necho invalid-json\n", encoding="utf-8")
        bad.chmod(0o700)
        controller.RUST_USER_SERVICE_ACTION_BIN = bad
        state_file.write_text("inactive", encoding="utf-8")
        failed = controller.service_action("lan-share", "start")
        assert failed["ok"] is False and "backend returned invalid state" in failed["message"]
        assert state_file.read_text(encoding="utf-8") == "inactive"
    print(f"Arch Remote user-service action and fallback parity: {count} cases passed")


if __name__ == "__main__":
    main()
