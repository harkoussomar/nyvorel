#!/usr/bin/env python3
"""Isolated native runtime route check; no host service or display is changed."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

CRATE = Path(__file__).resolve().parents[1]
BINARY = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else CRATE / "target/release/nyvorel-arch-remote"
LAUNCHER = CRATE.parent.parent / "quickshell/scripts/arch-remote/nyvorel-arch-remote"
CLI = CRATE / "arch-remote"


def call(executable, env, *args, timeout=30):
    output = subprocess.run([str(executable), *args], env=env, text=True,
                            capture_output=True, check=True, timeout=timeout)
    return json.loads(output.stdout)


def main():
    with tempfile.TemporaryDirectory(prefix="arch-remote-native-") as temporary:
        root = Path(temporary)
        home = root / "home"
        home.mkdir()
        runtime = root / "runtime"
        runtime.mkdir()
        shell = home / ".config/quickshell/nyvorel"
        scripts = shell / "scripts"
        (scripts / "system").mkdir(parents=True)
        (scripts / "arch-remote").mkdir()
        binary = scripts / "system/nyvorel-arch-remote"
        shutil.copy2(BINARY, binary)
        launcher = scripts / "arch-remote/nyvorel-arch-remote"
        shutil.copy2(LAUNCHER, launcher)
        launcher.chmod(0o755)
        legacy_marker = root / "python-was-called"
        (scripts / "arch-remote/control_center.py").write_text(
            f"from pathlib import Path\nPath({str(legacy_marker)!r}).touch()\nraise SystemExit(99)\n")
        fakebin = root / "bin"
        fakebin.mkdir()
        systemctl_calls = root / "systemctl-calls"
        systemctl = fakebin / "systemctl"
        systemctl.write_text(
            "#!/bin/sh\n"
            "printf '%s\\n' \"$*\" >> \"$FAKE_SYSTEMCTL_CALLS\"\n"
            "case \"$*\" in *show*) printf 'LoadState=loaded\\nActiveState=inactive\\n' ;; esac\n")
        systemctl.chmod(0o755)
        env = {**os.environ, "HOME": str(home), "USER": "isolated",
               "XDG_RUNTIME_DIR": str(runtime), "NYVOREL_ROOT": str(shell),
               "PATH": f"{fakebin}:/usr/bin:/bin", "FAKE_SYSTEMCTL_CALLS": str(systemctl_calls)}

        assert call(launcher, env, "contract")["ok"] is True
        assert call(launcher, env, "selftest")["ok"] is True
        state = call(launcher, env, "snapshot", timeout=35)
        assert state["schema_version"] == 2 and len(state["security_checks"]) == 15
        assert call(launcher, env, "reference", timeout=35)["ok"] is True
        assert call(launcher, env, "pairing-capability", timeout=35)["ok"] is True
        assert call(launcher, env, "operation-start", "service", "unknown", "start")["error"] is True
        # A synthetic action may fail readiness, but it must complete in the Rust worker.
        started = call(launcher, env, "operation-start", "service", "lan-share", "start")
        assert started["ok"] is True
        finished = call(launcher, env, "operation-wait", started["operation"]["id"], "20")
        assert finished["operation"]["active"] is False, finished
        assert systemctl_calls.is_file() and "--user start lan-share" in systemctl_calls.read_text()
        cli = root / "arch-remote"
        shutil.copy2(CLI, cli)
        cli.chmod(0o755)
        result = subprocess.run([str(cli), "status"], env=env, text=True,
                                capture_output=True, check=True, timeout=35)
        assert "ARCH REMOTE STATUS" in result.stdout
        assert not legacy_marker.exists(), "Legacy Python controller was launched"
    print("Full native Arch Remote: panel launcher, live state, reference, pairing, worker, CLI passed")


if __name__ == "__main__":
    main()
