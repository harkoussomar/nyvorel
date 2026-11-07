#!/usr/bin/env python3
"""Wake, linger, and lid evidence parity with disposable command output."""
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


def expected(interfaces):
    return {"wake": controller.wake_state(interfaces), "linger": controller.linger_state(), "lid": controller.lid_state()}


def rust(interfaces):
    result = subprocess.run([str(RUST), "power"], input=json.dumps(interfaces),
                            capture_output=True, text=True, check=True, timeout=20)
    assert result.stderr == "", result.stderr
    return json.loads(result.stdout)


def main():
    controller.RUST_POWER_BIN = RUST
    with tempfile.TemporaryDirectory(prefix="nyvorel-arch-power-") as directory:
        root = Path(directory)
        fake_bin = root / "bin"
        fake_bin.mkdir()
        fixtures = {
            "ethtool": "Supports Wake-on: pumbg\nWake-on: g\n",
            "iw": "WoWLAN magic packet\n",
            "loginctl": "yes\n",
            "systemctl": "Wed 2020-01-01 00:00:00 UTC\n",
            "date": "1577836800\n",
        }
        for name, output in fixtures.items():
            script = fake_bin / name
            script.write_text(f"#!/bin/sh\nprintf '%b' {output!r}\n", encoding="utf-8")
            script.chmod(0o755)
        old_path = os.environ.get("PATH")
        os.environ["PATH"] = f"{fake_bin}:/usr/bin:/bin"
        try:
            cases = [
                [],
                [{"name": "eth-test", "mac": "aa:bb:cc:dd:ee:ff", "physical": True,
                  "wireless": False, "loopback": False, "tailscale": False}],
                [{"name": "eth-test", "mac": "aa:bb:cc:dd:ee:ff", "physical": True,
                  "wireless": False, "loopback": False, "tailscale": False},
                 {"name": "wlan-test", "mac": "11:22:33:44:55:66", "physical": True,
                  "wireless": True, "loopback": False, "tailscale": False}],
            ]
            for interfaces in cases:
                result = expected(interfaces)
                assert rust(interfaces) == result
                wake, linger, lid = controller.snapshot_power_state(interfaces)
                assert {"wake": wake, "linger": linger, "lid": lid} == result
            bad = root / "bad"
            bad.write_text("#!/bin/sh\necho invalid-json\n", encoding="utf-8")
            bad.chmod(0o755)
            controller.RUST_POWER_BIN = bad
            wake, linger, lid = controller.snapshot_power_state(interfaces)
            assert {"wake": wake, "linger": linger, "lid": lid} == expected(interfaces)
        finally:
            if old_path is None:
                os.environ.pop("PATH", None)
            else:
                os.environ["PATH"] = old_path
    print("Arch Remote power evidence and fallback parity: passed")


if __name__ == "__main__":
    main()
