#!/usr/bin/env python3
"""Install or roll back the on-demand Rust wallpaper color helpers.

Only executable code is switched. Live wallpaper, config, and generated colors
are not touched by this installer.
"""

import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import shlex
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CRATE = Path(__file__).resolve().parent
ACTIVE = Path.home() / ".config/quickshell/nyvorel"
BACKUPS = ROOT / ".migration-backups"
STATE = Path.home() / ".config/nyvorel/appearance-studio.json"
FILES = {
    "nyvorel-appearance-studio": (
        CRATE / "target/release/nyvorel-appearance-studio",
        ACTIVE / "scripts/system/nyvorel-appearance-studio",
        None,
    ),
    "switchwall.sh": (
        ROOT / "quickshell/scripts/colors/switchwall.sh",
        ACTIVE / "scripts/colors/switchwall.sh",
        "color_python",
    ),
    "applycolor.sh": (
        ROOT / "quickshell/scripts/colors/applycolor.sh",
        ACTIVE / "scripts/colors/applycolor.sh",
        "changeAdwColors.py",
    ),
    "materialQT.sh": (
        ROOT / "quickshell/scripts/kvantum/materialQT.sh",
        ACTIVE / "scripts/kvantum/materialQT.sh",
        "adwsvgDark.py",
    ),
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def atomic_copy(source, destination, mode):
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".wallpaper-color-", dir=destination.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(source.read_bytes())
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(name, mode)
        os.replace(name, destination)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def verify():
    for label, (source, target, _) in FILES.items():
        if not source.is_file() or not target.is_file() or digest(source) != digest(target):
            raise RuntimeError(f"Active {label} differs from the tested project file")
        if not os.access(target, os.X_OK):
            raise RuntimeError(f"Active {label} is not executable")
    print("Active wallpaper color code matches the tested Rust build")


def restore(snapshot, check_installed=True):
    manifest = json.loads((snapshot / "manifest.json").read_text())["files"]
    if check_installed:
        for label, (_, target, _) in FILES.items():
            record = manifest[label]
            if str(target) != record["path"] or not target.is_file() or digest(target) != record["installed_sha256"]:
                raise RuntimeError(f"Active {label} changed after installation; refusing rollback")
    for label in ("switchwall.sh", "applycolor.sh", "materialQT.sh", "nyvorel-appearance-studio"):
        _, target, _ = FILES[label]
        record = manifest[label]
        backup = snapshot / label
        if digest(backup) != record["previous_sha256"]:
            raise RuntimeError(f"Rollback copy is damaged: {label}")
        atomic_copy(backup, target, record["mode"])


def install():
    if STATE.is_file() and json.loads(STATE.read_text()).get("preview"):
        raise RuntimeError("Appearance Studio preview is active; keep or revert it before upgrading")
    for label, (source, target, old_marker) in FILES.items():
        if not source.is_file() or not target.is_file():
            raise RuntimeError(f"Source or active file missing: {label}")
        if old_marker and digest(source) != digest(target) and old_marker not in target.read_text():
            raise RuntimeError(f"Active {label} is not the expected previous version")
    snapshot = BACKUPS / ("wallpaper-color-" + datetime.now().strftime("%Y%m%d-%H%M%S"))
    snapshot.mkdir(parents=True, exist_ok=False)
    manifest = {"files": {}}
    for label, (source, target, _) in FILES.items():
        mode = target.stat().st_mode & 0o777
        atomic_copy(target, snapshot / label, mode)
        manifest["files"][label] = {
            "path": str(target), "mode": mode,
            "previous_sha256": digest(target),
            "installed_sha256": digest(source),
        }
    (snapshot / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    rollback = snapshot / "rollback.sh"
    rollback.write_text("#!/bin/sh\nexec python3 " + shlex.quote(str(Path(__file__).resolve()))
                        + " rollback " + shlex.quote(str(snapshot)) + "\n")
    rollback.chmod(0o755)
    try:
        for _, (source, target, _) in FILES.items():
            atomic_copy(source, target, 0o755)
        verify()
    except Exception:
        restore(snapshot, check_installed=False)
        raise
    print(f"Installed. Rollback: {rollback}")


def refresh(snapshot):
    """Update a tested binary while retaining the pre-migration rollback."""
    manifest_path = snapshot / "manifest.json"
    original = manifest_path.read_bytes()
    manifest = json.loads(original)
    changed = []
    for label, (source, target, _) in FILES.items():
        record = manifest["files"][label]
        if record["path"] != str(target) or not target.is_file():
            raise RuntimeError(f"Snapshot does not describe active {label}")
        if digest(target) != record["installed_sha256"]:
            raise RuntimeError(f"Active {label} changed after installation; refusing refresh")
        if not source.is_file():
            raise RuntimeError(f"Project source missing: {label}")
        if digest(source) != digest(target):
            changed.append(label)
    if not changed:
        verify()
        print("Active wallpaper color code already matches the project build")
        return
    with tempfile.TemporaryDirectory(prefix=".color-refresh-", dir=snapshot) as temporary:
        temporary = Path(temporary)
        try:
            for label in changed:
                source, target, _ = FILES[label]
                atomic_copy(target, temporary / label, target.stat().st_mode & 0o777)
                atomic_copy(source, target, target.stat().st_mode & 0o777)
                manifest["files"][label]["installed_sha256"] = digest(source)
            verify()
            staged = temporary / "manifest.json"
            staged.write_text(json.dumps(manifest, indent=2) + "\n")
            os.replace(staged, manifest_path)
        except Exception:
            for label in changed:
                backup = temporary / label
                if backup.is_file():
                    _, target, _ = FILES[label]
                    atomic_copy(backup, target, backup.stat().st_mode & 0o777)
            manifest_path.write_bytes(original)
            raise
    print(f"Refreshed {', '.join(changed)}; original rollback retained: {snapshot / 'rollback.sh'}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("install", "verify", "refresh", "rollback"))
    parser.add_argument("snapshot", nargs="?")
    args = parser.parse_args()
    if args.action == "install":
        install()
    elif args.action == "verify":
        verify()
    elif args.action == "refresh":
        if not args.snapshot:
            parser.error("refresh needs a snapshot path")
        refresh(Path(args.snapshot))
    else:
        if not args.snapshot:
            parser.error("rollback needs a snapshot path")
        restore(Path(args.snapshot))
        print("Previous wallpaper color code restored; appearance data preserved")


if __name__ == "__main__":
    main()
