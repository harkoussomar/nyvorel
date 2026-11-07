#!/usr/bin/env python3
"""Exact listener parsing parity with disposable `ss` output."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[3]
PYTHON = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else ROOT / "quickshell/scripts/arch-remote/control_center.py"
RUST = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "target/release/nyvorel-arch-remote"
IPV4 = "100.101.102.103"
IPV6 = "fd7a:115c:a1e0::42"


def python(env, *, function="listeners_state", rust_path=None):
    code = ("import importlib.util,json;"
            f"s=importlib.util.spec_from_file_location('control_center',{str(PYTHON)!r});"
            "m=importlib.util.module_from_spec(s);s.loader.exec_module(m);"
            + (f"m.RUST_LISTENERS_BIN=m.Path({str(rust_path)!r});" if rust_path else "")
            + f"print(json.dumps(m.{function}({{'ipv4':{IPV4!r},'ipv6':{IPV6!r}}})))")
    result = subprocess.run([sys.executable, "-c", code], env=env, capture_output=True, text=True, check=True, timeout=15)
    assert result.stderr == "", result.stderr
    return json.loads(result.stdout)


def rust(env):
    result = subprocess.run([str(RUST), "listeners", IPV4, IPV6], env=env, capture_output=True, text=True, check=True, timeout=10)
    assert result.stderr == "", result.stderr
    return json.loads(result.stdout)


def main():
    with tempfile.TemporaryDirectory(prefix="nyvorel-arch-listeners-") as directory:
        root = Path(directory)
        fake_bin = root / "bin"
        fake_bin.mkdir()
        ss = fake_bin / "ss"
        ss.write_text('#!/bin/sh\ncase " $* " in *" -lntp "*) if [ "$ARCH_REMOTE_SS_FAIL" = 1 ]; then exit 1; fi;; esac\ncat "$ARCH_REMOTE_SS_FIXTURE"\n', encoding="utf-8")
        ss.chmod(0o755)
        fixture = root / "ss.txt"
        env = os.environ.copy()
        env.update(PATH=f"{fake_bin}:/usr/bin:/bin", ARCH_REMOTE_SS_FIXTURE=str(fixture), ARCH_REMOTE_SS_FAIL="0")
        cases = (
            "LISTEN 0 4096 127.0.0.1:8000 0.0.0.0:* users:((\"python3\",pid=123,fd=3))\n"
            "LISTEN 0 128 [::1]:22 [::]:* users:((\"sshd\",pid=90,fd=4))\n"
            f"LISTEN 0 32 [{IPV6}]:5900 [::]:* users:((\"wayvnc\",pid=77,fd=5))\n"
            "LISTEN 0 128 0.0.0.0:22 0.0.0.0:*\n"
            f"LISTEN 0 128 {IPV4}:443 0.0.0.0:*\n"
            "LISTEN 0 128 100.44.55.66:80 0.0.0.0:*\n"
            "LISTEN 0 128 *:9999 *:*\n"
            "LISTEN 0 128 192.168.1.3:8443 0.0.0.0:*\n"
            "LISTEN 0 128 127.0.0.1:0 0.0.0.0:*\n"
            "malformed row\n",
            "",
        )
        for output in cases:
            fixture.write_text(output, encoding="utf-8")
            expected = python(env)
            assert rust(env) == expected
            assert python(env, function="snapshot_listeners_state", rust_path=RUST) == expected
        fixture.write_text(cases[0], encoding="utf-8")
        bad_binary = root / "invalid-collector"
        bad_binary.write_text("#!/bin/sh\necho invalid-json\n", encoding="utf-8")
        bad_binary.chmod(0o755)
        assert python(env, function="snapshot_listeners_state", rust_path=bad_binary) == python(env)
        env["ARCH_REMOTE_SS_FAIL"] = "1"
        assert rust(env) == python(env)
        env["PATH"] = str(root / "empty")
        assert rust(env) == python(env)
        print("Arch Remote listener collector parity: passed")


if __name__ == "__main__":
    main()
