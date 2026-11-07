#!/usr/bin/env python3
"""Refresh audited one-shot Rust user binaries with a code-only rollback."""

from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import shlex
import tempfile


ROOT = Path(__file__).resolve().parent.parent
ACTIVE = Path.home() / ".config/quickshell/nyvorel"
BACKUPS = ROOT / ".migration-backups"
FILES = {
    "nyvorel-operations": (
        ROOT / "rust/operations-center/target/release/nyvorel-operations",
        ACTIVE / "scripts/system/nyvorel-operations",
    ),
    "nyvorel-backup-recovery": (
        ROOT / "rust/backup-recovery/target/release/nyvorel-backup-recovery",
        ACTIVE / "scripts/system/nyvorel-backup-recovery",
    ),
}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def atomic_copy(source: Path, destination: Path, mode: int) -> None:
    if destination.is_symlink():
        raise RuntimeError(f"Refusing symlink target: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, staging = tempfile.mkstemp(prefix=".nyvorel-rust-refresh-", dir=destination.parent)
    try:
        with os.fdopen(descriptor, "wb") as output:
            output.write(source.read_bytes())
            output.flush()
            os.fsync(output.fileno())
        os.chmod(staging, mode)
        os.replace(staging, destination)
    finally:
        if os.path.exists(staging):
            os.unlink(staging)


def verify() -> None:
    for label, (source, active) in FILES.items():
        if not source.is_file() or not active.is_file() or digest(source) != digest(active):
            raise RuntimeError(f"Active {label} differs from the tested build")
        if not os.access(active, os.X_OK):
            raise RuntimeError(f"Active {label} is not executable")
    print("Audited user-level Rust binaries match their source builds")


def restore(snapshot: Path, check_installed: bool = True) -> None:
    manifest = json.loads((snapshot / "manifest.json").read_text())["files"]
    if check_installed:
        for label, (_, active) in FILES.items():
            item = manifest[label]
            if str(active) != item["path"] or not active.is_file() or digest(active) != item["installed_sha256"]:
                raise RuntimeError(f"Active {label} changed since refresh; refusing rollback")
    for label, (_, active) in FILES.items():
        item = manifest[label]
        saved = snapshot / label
        if digest(saved) != item["previous_sha256"]:
            raise RuntimeError(f"Damaged backup: {saved}")
        atomic_copy(saved, active, item["mode"])


def install() -> None:
    for label, (source, active) in FILES.items():
        if not source.is_file() or not active.is_file() or active.is_symlink():
            raise RuntimeError(f"Missing or unsafe source/active binary: {label}")
    snapshot = BACKUPS / ("rust-user-binaries-" + datetime.now().strftime("%Y%m%d-%H%M%S"))
    snapshot.mkdir(parents=True, exist_ok=False)
    manifest = {"files": {}}
    for label, (source, active) in FILES.items():
        mode = active.stat().st_mode & 0o777
        atomic_copy(active, snapshot / label, mode)
        manifest["files"][label] = {
            "path": str(active), "mode": mode,
            "previous_sha256": digest(active), "installed_sha256": digest(source),
        }
    (snapshot / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    rollback = snapshot / "rollback.sh"
    rollback.write_text("#!/bin/sh\nexec python3 " + shlex.quote(str(Path(__file__).resolve()))
                        + " rollback " + shlex.quote(str(snapshot)) + "\n")
    rollback.chmod(0o755)
    try:
        for source, active in FILES.values():
            atomic_copy(source, active, 0o755)
        verify()
    except Exception:
        restore(snapshot, check_installed=False)
        raise
    print(f"Installed. Rollback: {rollback}")


def refresh(snapshot: Path) -> None:
    """Replace a tested build while retaining the original rollback files."""
    manifest_path = snapshot / "manifest.json"
    original_manifest = manifest_path.read_bytes()
    manifest = json.loads(original_manifest)["files"]
    changed = []
    for label, (source, active) in FILES.items():
        item = manifest[label]
        if (str(active) != item["path"] or not active.is_file()
                or digest(active) != item["installed_sha256"] or not source.is_file()):
            raise RuntimeError(f"Active {label} changed or source is missing; refusing refresh")
        if digest(source) != digest(active):
            changed.append(label)
    if not changed:
        verify()
        return
    with tempfile.TemporaryDirectory(prefix=".refresh-", dir=snapshot) as temporary:
        temporary = Path(temporary)
        try:
            for label in changed:
                source, active = FILES[label]
                atomic_copy(active, temporary / label, active.stat().st_mode & 0o777)
                atomic_copy(source, active, 0o755)
                manifest[label]["installed_sha256"] = digest(source)
            verify()
            updated = temporary / "manifest.json"
            updated.write_text(json.dumps({"files": manifest}, indent=2) + "\n")
            os.replace(updated, manifest_path)
        except Exception:
            for label in changed:
                saved = temporary / label
                if saved.is_file():
                    atomic_copy(saved, FILES[label][1], saved.stat().st_mode & 0o777)
            manifest_path.write_bytes(original_manifest)
            raise
    print(f"Refreshed {', '.join(changed)}; original rollback retained: {snapshot / 'rollback.sh'}")


def main() -> None:
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
        print("Previous user-level Rust binaries restored")


if __name__ == "__main__":
    main()
