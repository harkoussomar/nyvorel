#!/usr/bin/env python3
"""Compare the read-only systemd collector against Python with isolated units."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[3]
PYTHON = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else ROOT / "quickshell/scripts/arch-remote/control_center.py"
RUST = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "target/release/nyvorel-arch-remote"


def run_python(env, *, function="services_state", rust_path=None):
    code = ("import importlib.util,json;"
            f"s=importlib.util.spec_from_file_location('control_center',{str(PYTHON)!r});"
            "m=importlib.util.module_from_spec(s);s.loader.exec_module(m);"
            + (f"m.RUST_SERVICES_BIN=m.Path({str(rust_path)!r});" if rust_path else "")
            + f"print(json.dumps(m.{function}()))")
    result = subprocess.run([sys.executable, "-c", code], env=env, capture_output=True, text=True, check=True, timeout=20)
    assert result.stderr == "", result.stderr
    return json.loads(result.stdout)


def run_rust(env):
    result = subprocess.run([str(RUST), "services"], env=env, capture_output=True, text=True, check=True, timeout=10)
    assert result.stderr == "", result.stderr
    return json.loads(result.stdout)


def main():
    with tempfile.TemporaryDirectory(prefix="nyvorel-arch-services-") as directory:
        root = Path(directory)
        fake_bin = root / "bin"
        fixtures = root / "fixtures"
        fake_bin.mkdir()
        fixtures.mkdir()
        systemctl = fake_bin / "systemctl"
        systemctl.write_text('#!/bin/sh\nfor arg do\n case "$arg" in sshd|tailscaled|lan-share|wayvnc-remote) unit=$arg;; esac\ndone\ncat "$ARCH_REMOTE_FIXTURES/$unit"\n', encoding="utf-8")
        systemctl.chmod(0o755)
        env = os.environ.copy()
        env.update(PATH=f"{fake_bin}:/usr/bin:/bin", ARCH_REMOTE_FIXTURES=str(fixtures))
        cases = (
            {
                "sshd": "LoadState=loaded\nActiveState=active\nSubState=running\nUnitFileState=enabled\nMainPID=1234\nNRestarts=2\nActiveEnterTimestamp=Wed 2026-11-04 01:00:00 UTC\nFragmentPath=/usr/lib/systemd/system/sshd.service\nMemoryCurrent=1048576\nCPUUsageNSec=1500000000\nResult=success\nExecMainStatus=0\n",
                "tailscaled": "LoadState=loaded\nActiveState=inactive\nSubState=dead\nUnitFileState=enabled-runtime\nMemoryCurrent=0\nCPUUsageNSec=0\n",
                "lan-share": "LoadState=loaded\nActiveState=failed\nSubState=failed\nUnitFileState=static\nMemoryCurrent=2560\nCPUUsageNSec=61000000000\n",
                "wayvnc-remote": "LoadState=not-found\nActiveState=inactive\nUnitFileState=disabled\n",
            },
            {"sshd": "LoadState=loaded\nActiveState=active\nMemoryCurrent=infinity\nCPUUsageNSec=invalid\n",
             "tailscaled": "LoadState=loaded\nActiveState=failed\nMemoryCurrent=1536\nCPUUsageNSec=86400000000000\n",
             "lan-share": "LoadState=loaded\nActiveState=inactive\nMemoryCurrent=18446744073709551615\n",
             "wayvnc-remote": ""},
            {"sshd": "LoadState=loaded\nActiveState=active\nMemoryCurrent=-1\n",
             "tailscaled": "", "lan-share": "", "wayvnc-remote": ""},
        )
        for case in cases:
            for unit, output in case.items():
                (fixtures / unit).write_text(output, encoding="utf-8")
            left, right = run_python(env), run_rust(env)
            assert left == right, (left, right)
            assert run_python(env, function="snapshot_services_state", rust_path=RUST) == left
        bad_binary = root / "invalid-collector"
        bad_binary.write_text("#!/bin/sh\necho invalid-json\n", encoding="utf-8")
        bad_binary.chmod(0o755)
        assert run_python(env, function="snapshot_services_state", rust_path=bad_binary) == run_python(env)
        env["PATH"] = str(root / "empty")
        assert run_python(env) == run_rust(env)
        print("Arch Remote service collector parity: passed")


if __name__ == "__main__":
    main()
