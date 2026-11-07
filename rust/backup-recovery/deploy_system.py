#!/usr/bin/env python3
"""Install or roll back the on-demand Rust system services.

Only deployment uses Python; no Python process remains in the service path.
Run with root privileges after building the release binary. The installer
preserves the original units and drop-ins and rolls back failed verification.
"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from datetime import datetime


ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(__file__).resolve().parent / "target/release/nyvorel-backup-recovery-root"
DEST = Path("/usr/local/lib/backup-recovery/nyvorel-backup-recovery-root")
UNITS = ("state", "backup", "timeshift", "restic-check", "restore-test",
         "smart-short", "smart-long", "mount", "eject", "refresh-manifests")
DROPIN_NAME = "90-nyvorel-rust.conf"
SNAPSHOTS = ROOT / ".migration-backups"


def systemctl(*args):
    return subprocess.run(("/usr/bin/systemctl", *args), text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=60, check=False)


def dropin(action):
    return (Path("/etc/systemd/system") /
            f"backup-recovery-{action}.service.d" / DROPIN_NAME)


def snapshot():
    name = "backup-recovery-full-rust-" + datetime.now().strftime("%Y%m%d-%H%M%S")
    directory = SNAPSHOTS / name
    directory.mkdir(parents=True, mode=0o700)
    manifest = {"old_binary": DEST.exists(), "dropins": {}}
    if DEST.exists():
        shutil.copy2(DEST, directory / "previous-root-binary")
    units_dir = directory / "units"
    units_dir.mkdir()
    for action in UNITS:
        unit = Path("/etc/systemd/system") / f"backup-recovery-{action}.service"
        if not unit.is_file():
            raise RuntimeError(f"Missing system service: {unit}")
        shutil.copy2(unit, units_dir / unit.name)
        previous = dropin(action)
        manifest["dropins"][action] = previous.exists()
        if previous.exists():
            shutil.copy2(previous, directory / f"previous-{action}.conf")
    (directory / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (directory / "ROLLBACK.txt").write_text(
        f"Restore with: pkexec /usr/bin/python3 {Path(__file__).resolve()} rollback {directory}\n")
    # pkexec starts as root, but the invoking user must be able to inspect the
    # rollback bundle. It contains only service definitions and the old binary.
    owner = os.environ.get("PKEXEC_UID")
    if owner is not None:
        uid = int(owner)
        for path in (directory, *directory.rglob("*")):
            os.chown(path, uid, -1)
    return directory


def restore(directory):
    directory = directory.resolve(strict=True)
    if directory.parent != SNAPSHOTS.resolve():
        raise RuntimeError("Rollback snapshot is outside the migration backup directory")
    manifest = json.loads((directory / "manifest.json").read_text())
    for action in UNITS:
        target = dropin(action)
        if manifest["dropins"][action]:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(directory / f"previous-{action}.conf", target)
        else:
            target.unlink(missing_ok=True)
    if manifest["old_binary"]:
        shutil.copy2(directory / "previous-root-binary", DEST)
    else:
        DEST.unlink(missing_ok=True)
    result = systemctl("daemon-reload")
    if result.returncode:
        raise RuntimeError(f"systemd reload failed: {result.stderr.strip()}")


def install():
    if not SOURCE.is_file() or not os.access(SOURCE, os.X_OK):
        raise RuntimeError(f"Build the release binary first: {SOURCE}")
    for action in UNITS:
        if action == "state":
            continue
        state = systemctl("is-active", f"backup-recovery-{action}.service")
        if state.stdout.strip() in ("active", "activating", "reloading"):
            raise RuntimeError(f"Action still running: backup-recovery-{action}.service")
    directory = snapshot()
    try:
        DEST.parent.mkdir(parents=True, exist_ok=True)
        staged = DEST.with_name(DEST.name + ".new")
        shutil.copy2(SOURCE, staged)
        staged.chmod(0o755)
        os.replace(staged, DEST)
        for action in UNITS:
            target = dropin(action)
            target.parent.mkdir(parents=True, exist_ok=True)
            command = "collect" if action == "state" else action
            target.write_text(
                "[Service]\nExecStart=\n"
                f"ExecStart={DEST} {command}\n"
            )
            target.chmod(0o644)
        result = systemctl("daemon-reload")
        if result.returncode:
            raise RuntimeError(f"systemd reload failed: {result.stderr.strip()}")
        for action in UNITS:
            result = systemctl("show", f"backup-recovery-{action}.service", "-p", "ExecStart")
            if result.returncode or str(DEST) not in result.stdout:
                raise RuntimeError(f"Rust command not active for {action}: {result.stderr.strip()}")
        result = systemctl("start", "backup-recovery-state.service")
        if result.returncode:
            raise RuntimeError(f"Rust state collector failed: {result.stderr.strip()}")
        state = json.loads(Path("/var/lib/backup-recovery/state.json").read_text())
        if state.get("schema_version") != 2 or state.get("ui_contract") != "1.6.0":
            raise RuntimeError("Rust state collector produced an incompatible UI contract")
    except Exception:
        restore(directory)
        raise
    print(f"Installed Rust services. Rollback snapshot: {directory}")


def main():
    if os.geteuid() != 0:
        raise RuntimeError("System service deployment requires root privileges")
    if len(sys.argv) == 2 and sys.argv[1] == "install":
        install()
    elif len(sys.argv) == 3 and sys.argv[1] == "rollback":
        restore(Path(sys.argv[2]))
        print(f"Restored service commands from {sys.argv[2]}")
    else:
        raise RuntimeError("Usage: deploy_system.py install | rollback SNAPSHOT")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"Backup & Recovery service deployment: {error}", file=sys.stderr)
        sys.exit(1)
