#!/usr/bin/env python3
"""Switch the active Settings radius bridge to Rust with a code-only rollback."""

from __future__ import annotations

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
    "binary": (CRATE / "target/release/nyvorel-appearance-studio",
               ACTIVE / "scripts/system/nyvorel-appearance-studio"),
    "InterfaceConfig.qml": (ROOT / "quickshell/modules/settings/InterfaceConfig.qml",
                            ACTIVE / "modules/settings/InterfaceConfig.qml"),
}
OLD_CALL = f'"{Path.home()}/.config/quickshell/nyvorel/scripts/appearance-studio/semantic_radius_hypr.py",'
NEW_CALL = 'Quickshell.shellPath("scripts/system/nyvorel-appearance-studio"),\n                "__semantic-radius",'


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def atomic_copy(source: Path, destination: Path, mode: int) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, staging = tempfile.mkstemp(prefix=".semantic-radius-", dir=destination.parent)
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


def verify() -> None:
    for label, (source, target) in FILES.items():
        if not source.is_file() or not target.is_file() or digest(source) != digest(target):
            raise RuntimeError(f"Active {label} differs from the tested project file")
    if not os.access(FILES["binary"][1], os.X_OK):
        raise RuntimeError("Active Rust binary is not executable")
    print("Active Settings radius caller and Rust binary match the tested build")


def restore(snapshot: Path, check_installed: bool = True) -> None:
    manifest = json.loads((snapshot / "manifest.json").read_text())["files"]
    if check_installed:
        for label, (_, target) in FILES.items():
            record = manifest[label]
            if str(target) != record["path"] or not target.is_file() or digest(target) != record["installed_sha256"]:
                raise RuntimeError(f"Active {label} changed after installation; refusing rollback")
    for label in ("InterfaceConfig.qml", "binary"):
        _, target = FILES[label]
        record = manifest[label]
        previous = snapshot / label
        if digest(previous) != record["previous_sha256"]:
            raise RuntimeError(f"Rollback copy is damaged: {label}")
        atomic_copy(previous, target, record["mode"])


def install() -> None:
    if STATE.is_file() and json.loads(STATE.read_text()).get("preview"):
        raise RuntimeError("Appearance Studio preview is active; keep or revert it before upgrading")
    for label, (source, target) in FILES.items():
        if not source.is_file() or not target.is_file():
            raise RuntimeError(f"Source or active file missing: {label}")
    old_qml = FILES["InterfaceConfig.qml"][1].read_text()
    if old_qml.count(OLD_CALL) != 1 or old_qml.replace(OLD_CALL, NEW_CALL) != FILES["InterfaceConfig.qml"][0].read_text():
        raise RuntimeError("Active Settings QML has changes beyond the expected Python radius call")
    snapshot = BACKUPS / ("semantic-radius-" + datetime.now().strftime("%Y%m%d-%H%M%S"))
    snapshot.mkdir(parents=True, exist_ok=False)
    manifest = {"files": {}}
    for label, (source, target) in FILES.items():
        mode = target.stat().st_mode & 0o777
        atomic_copy(target, snapshot / label, mode)
        manifest["files"][label] = {
            "path": str(target), "mode": mode,
            "previous_sha256": digest(target), "installed_sha256": digest(source),
        }
    (snapshot / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    rollback = snapshot / "rollback.sh"
    rollback.write_text("#!/bin/sh\nexec python3 " + shlex.quote(str(Path(__file__).resolve()))
                        + " rollback " + shlex.quote(str(snapshot)) + "\n")
    rollback.chmod(0o755)
    try:
        for label, (source, target) in FILES.items():
            atomic_copy(source, target, 0o755 if label == "binary" else 0o644)
        verify()
    except Exception:
        restore(snapshot, check_installed=False)
        raise
    print(f"Installed. Rollback: {rollback}")


def main() -> None:
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
        print("Previous radius bridge restored; live appearance data preserved")


if __name__ == "__main__":
    main()
