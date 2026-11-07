#!/usr/bin/env python3
"""Install or roll back the active one-shot keybind parser."""

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
FILES = {
    "nyvorel-keybinds": (
        CRATE / "target/release/nyvorel-keybinds",
        ACTIVE / "scripts/system/nyvorel-keybinds",
    ),
    "HyprlandKeybinds.qml": (
        ROOT / "quickshell/services/HyprlandKeybinds.qml",
        ACTIVE / "services/HyprlandKeybinds.qml",
    ),
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def atomic_copy(source, destination, mode):
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, staging = tempfile.mkstemp(prefix=".nyvorel-keybinds-", dir=destination.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(source.read_bytes())
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(staging, mode)
        os.replace(staging, destination)
    finally:
        if os.path.exists(staging):
            os.unlink(staging)


def verify():
    for label, (source, target) in FILES.items():
        if not source.is_file() or not target.is_file() or digest(source) != digest(target):
            raise RuntimeError(f"Active {label} does not match the tested project file")
    if not os.access(FILES["nyvorel-keybinds"][1], os.X_OK):
        raise RuntimeError("Active keybind parser is not executable")
    print("Active keybind parser and QML caller match the tested build")


def restore(snapshot, check_installed=True):
    manifest = json.loads((snapshot / "manifest.json").read_text())["files"]
    if check_installed:
        for label, (_, target) in FILES.items():
            record = manifest[label]
            if record["path"] != str(target) or not target.is_file() or digest(target) != record["installed_sha256"]:
                raise RuntimeError(f"Active {label} changed after installation; refusing rollback")
    for label in ("HyprlandKeybinds.qml", "nyvorel-keybinds"):
        _, target = FILES[label]
        record = manifest[label]
        if record["existed"]:
            source = snapshot / label
            if digest(source) != record["previous_sha256"]:
                raise RuntimeError(f"Rollback copy is damaged: {label}")
            atomic_copy(source, target, record["mode"])
        else:
            target.unlink(missing_ok=True)


def install():
    old_caller = FILES["HyprlandKeybinds.qml"][1]
    if not old_caller.is_file() or "get_keybinds.py" not in old_caller.read_text():
        raise RuntimeError("Active QML caller is not the expected Python version")
    for label, (source, _) in FILES.items():
        if not source.is_file():
            raise RuntimeError(f"Build output or source missing: {label}")
    snapshot = BACKUPS / ("keybinds-" + datetime.now().strftime("%Y%m%d-%H%M%S"))
    snapshot.mkdir(parents=True, exist_ok=False)
    manifest = {"files": {}}
    for label, (source, target) in FILES.items():
        existed = target.is_file()
        mode = target.stat().st_mode & 0o777 if existed else (0o644 if target.suffix == ".qml" else 0o755)
        if existed:
            atomic_copy(target, snapshot / label, mode)
        manifest["files"][label] = {
            "path": str(target), "existed": existed, "mode": mode,
            "previous_sha256": digest(target) if existed else None,
            "installed_sha256": digest(source),
        }
    (snapshot / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    rollback = snapshot / "rollback.sh"
    rollback.write_text("#!/bin/sh\nexec python3 " + shlex.quote(str(Path(__file__).resolve()))
                        + " rollback " + shlex.quote(str(snapshot)) + "\n")
    rollback.chmod(0o755)
    try:
        for label, (source, target) in FILES.items():
            atomic_copy(source, target, manifest["files"][label]["mode"])
        verify()
    except Exception:
        restore(snapshot, check_installed=False)
        raise
    print(f"Installed. Rollback: {rollback}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("install", "verify", "rollback"))
    parser.add_argument("snapshot", nargs="?")
    args = parser.parse_args()
    if args.action == "install":
        install()
    elif args.action == "verify":
        verify()
    else:
        if not args.snapshot:
            parser.error("rollback needs a snapshot path")
        restore(Path(args.snapshot))
        print("Previous keybind caller restored; keybind configuration preserved")


if __name__ == "__main__":
    main()
