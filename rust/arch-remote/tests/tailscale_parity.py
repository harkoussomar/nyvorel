#!/usr/bin/env python3
"""Compare Tailscale daemon-status parsing with isolated CLI fixtures."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[3]
PYTHON = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else ROOT / "quickshell/scripts/arch-remote/control_center.py"
RUST = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "target/release/nyvorel-arch-remote"


def python(env, *, function="tailscale_status", rust_path=None):
    code = ("import importlib.util,json;"
            f"s=importlib.util.spec_from_file_location('control_center',{str(PYTHON)!r});"
            "m=importlib.util.module_from_spec(s);s.loader.exec_module(m);"
            + (f"m.RUST_TAILSCALE_BIN=m.Path({str(rust_path)!r});" if rust_path else "")
            + f"print(json.dumps(m.{function}()))")
    result = subprocess.run([sys.executable, "-c", code], env=env, capture_output=True, text=True, check=True, timeout=15)
    assert result.stderr == "", result.stderr
    return json.loads(result.stdout)


def rust(env):
    result = subprocess.run([str(RUST), "tailscale-status"], env=env, capture_output=True, text=True, check=True, timeout=10)
    assert result.stderr == "", result.stderr
    return json.loads(result.stdout)


def main():
    with tempfile.TemporaryDirectory(prefix="nyvorel-arch-tailscale-") as directory:
        root = Path(directory)
        fake_bin = root / "bin"
        fake_bin.mkdir()
        fake = fake_bin / "tailscale"
        fake.write_text('#!/bin/sh\ncat "$ARCH_REMOTE_TS_FIXTURE"\nexit "$ARCH_REMOTE_TS_EXIT"\n', encoding="utf-8")
        fake.chmod(0o755)
        fixture = root / "tailscale.json"
        env = os.environ.copy()
        env.update(PATH=f"{fake_bin}:/usr/bin:/bin", ARCH_REMOTE_TS_FIXTURE=str(fixture), ARCH_REMOTE_TS_EXIT="0")
        cases = (
            {"BackendState": "Running", "Self": {"HostName": "laptop", "DNSName": "laptop.ts.net.",
                "TailscaleIPs": ["100.2.3.4", "fd7a:115c:a1e0::1"], "OS": "linux"},
             "Peer": {"z": {"HostName": "Phone S22", "DNSName": "phone.ts.net.", "TailscaleIPs": ["100.2.3.5"], "OS": "android", "Online": True},
                      "a": {"HostName": "desktop", "TailscaleIPs": ["100.2.3.6"], "Online": False}},
             "MagicDNSSuffix": "ts.net", "Health": []},
            {"BackendState": "Stopped", "Self": {"HostName": "laptop", "Online": False},
             "Peer": [{"HostName": "android tablet", "Online": False}, {"ComputedName": "other", "Active": True}],
             "CurrentTailnet": {"MagicDNSEnabled": True}, "Health": ["DNS warning"]},
            {"BackendState": "Running", "TailscaleIPs": ["100.9.9.9"], "Health": "single warning"},
            {},
        )
        for case in cases:
            fixture.write_text(json.dumps(case), encoding="utf-8")
            expected = python(env)
            assert rust(env) == expected, case
            assert python(env, function="snapshot_tailscale_status", rust_path=RUST) == expected, case
        fixture.write_text("not-json", encoding="utf-8")
        assert rust(env) == python(env)
        bad_binary = root / "invalid-collector"
        bad_binary.write_text("#!/bin/sh\necho invalid-json\n", encoding="utf-8")
        bad_binary.chmod(0o755)
        assert python(env, function="snapshot_tailscale_status", rust_path=bad_binary) == python(env)
        env["ARCH_REMOTE_TS_EXIT"] = "1"
        assert rust(env) == python(env)
        env["PATH"] = str(root / "empty")
        assert rust(env) == python(env)
        print("Arch Remote Tailscale status parity: passed")


if __name__ == "__main__":
    main()
