#!/usr/bin/env python3
"""Exact interface discovery parity with disposable iproute2 JSON."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[3]
PYTHON = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else ROOT / "quickshell/scripts/arch-remote/control_center.py"
RUST = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "target/release/nyvorel-arch-remote"


def python(env, function="interfaces_state", rust_path=None):
    code = ("import importlib.util,json;"
            f"s=importlib.util.spec_from_file_location('control_center',{str(PYTHON)!r});"
            "m=importlib.util.module_from_spec(s);s.loader.exec_module(m);"
            + (f"m.RUST_INTERFACES_BIN=m.Path({str(rust_path)!r});" if rust_path else "")
            + f"print(json.dumps(m.{function}()))")
    result = subprocess.run([sys.executable, "-c", code], env=env, capture_output=True, text=True, check=True, timeout=15)
    assert result.stderr == "", result.stderr
    return json.loads(result.stdout)


def rust(env):
    result = subprocess.run([str(RUST), "interfaces"], env=env, capture_output=True, text=True, check=True, timeout=10)
    assert result.stderr == "", result.stderr
    return json.loads(result.stdout)


def main():
    with tempfile.TemporaryDirectory(prefix="nyvorel-arch-interfaces-") as directory:
        root = Path(directory)
        fake_bin = root / "bin"
        fake_bin.mkdir()
        binary = fake_bin / "ip"
        binary.write_text('#!/bin/sh\nif [ "$ARCH_REMOTE_IP_FAIL" = 1 ]; then exit 1; fi\ncat "$ARCH_REMOTE_IP_FIXTURE"\n', encoding="utf-8")
        binary.chmod(0o755)
        fixture = root / "ip.json"
        env = os.environ.copy()
        env.update(PATH=f"{fake_bin}:/usr/bin:/bin", ARCH_REMOTE_IP_FIXTURE=str(fixture), ARCH_REMOTE_IP_FAIL="0")
        cases = [
            [{"ifname": "lo", "operstate": "UNKNOWN", "address": "00:00:00:00:00:00", "addr_info": [{"local": "127.0.0.1"}, {"local": "::1"}]},
             {"ifname": "tailscale0", "operstate": "UP", "addr_info": [{"local": "100.101.102.103"}]},
             {"ifname": "eth-test", "operstate": "DOWN", "addr_info": []}],
            [{"ifname": "", "addr_info": []}, {"ifname": "virtual-test", "addr_info": [{"local": "192.0.2.4"}, {}, {"local": "2001:db8::1"}]}],
            [],
        ]
        for case in cases:
            fixture.write_text(json.dumps(case), encoding="utf-8")
            expected = python(env)
            assert rust(env) == expected
            assert python(env, "snapshot_interfaces_state", RUST) == expected
        fixture.write_text("not-json", encoding="utf-8")
        assert rust(env) == python(env)
        invalid = root / "invalid-collector"
        invalid.write_text("#!/bin/sh\necho invalid-json\n", encoding="utf-8")
        invalid.chmod(0o755)
        assert python(env, "snapshot_interfaces_state", invalid) == python(env)
        env["ARCH_REMOTE_IP_FAIL"] = "1"
        assert rust(env) == python(env)
        env["PATH"] = str(root / "empty")
        assert rust(env) == python(env)
        print("Arch Remote interface collector parity: passed")


if __name__ == "__main__":
    main()
