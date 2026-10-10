#!/usr/bin/env python3
"""Repair only proven ii-to-Nyvorel renames in an existing Arch Remote manifest."""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import tempfile
import time


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def repaired_manifest(payload: dict, home: Path) -> tuple[dict, int]:
    """Reject unexplained content/mode changes; never bless arbitrary live files."""
    updated = copy.deepcopy(payload)
    files = updated.get("files")
    if not isinstance(files, list) or not files:
        raise ValueError("Manifest has no file inventory")
    legacy = home / ".config/quickshell/ii"
    current = home / ".config/quickshell/nyvorel"
    paths = {
        str(legacy / "scripts/arch-remote/control_center.py"):
            (current / "scripts/arch-remote/control_center.py", "backend"),
        str(legacy / "modules/ii/archRemote/ArchRemote.qml"):
            (current / "modules/nyvorel/archRemote/ArchRemote.qml", "qml"),
        str(legacy / "modules/ii/archRemote/ArchRemoteContent.qml"):
            (current / "modules/nyvorel/archRemote/ArchRemoteContent.qml", "qml"),
    }
    changed = 0
    for item in files:
        path = Path(item["path"])
        target, kind = paths.get(str(path), (path, "unchanged"))
        if str(path) in paths and path.exists():
            raise ValueError(f"Legacy path still exists; review both deployments: {path}")
        data = target.read_bytes()
        mode = f"{stat.S_IMODE(target.stat().st_mode):04o}"
        if item.get("mode") and mode != item["mode"]:
            raise ValueError(f"Unexplained mode change: {target}")
        if target == home / ".local/bin/arch-remote" and digest(data) != item["sha256"]:
            kind = "launcher"
        original = data
        if kind == "backend":
            original = data.replace(b'nyvorel/arch-remote', b'illogical-impulse/arch-remote')
        elif kind == "qml":
            original = data.replace(b'nyvorel', b'ii')
        elif kind == "launcher":
            original = data.replace(b'ROOT="${NYVOREL_ROOT:-$HOME/.config/quickshell/nyvorel}"',
                                    b'ROOT="${II_ROOT:-$HOME/.config/quickshell/ii}"')
        if digest(original) != item["sha256"]:
            raise ValueError(f"Unexplained content change; manifest left untouched: {target}")
        if str(target) != item["path"] or digest(data) != item["sha256"]:
            item.update(path=str(target), sha256=digest(data))
            changed += 1
    return updated, changed


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", type=Path, default=Path.home())
    parser.add_argument("--apply", action="store_true", help="Back up and atomically repair the manifest")
    args = parser.parse_args()
    home = args.home.resolve()
    manifest = home / ".local/state/nyvorel/arch-remote/deployment.json"
    payload = json.loads(manifest.read_text())
    updated, count = repaired_manifest(payload, home)
    print(f"Verified all {len(updated['files'])} entries; {count} proven rename(s).")
    if not args.apply or not count:
        return
    backup = manifest.with_name(f"deployment.before-nyvorel-repair-{time.time_ns()}.json")
    shutil.copy2(manifest, backup)
    updated["nyvorel_migration_repaired_at"] = time.time()
    fd, tmp = tempfile.mkstemp(prefix=".deployment-", dir=manifest.parent)
    try:
        with os.fdopen(fd, "w") as handle:
            json.dump(updated, handle, indent=2)
            handle.write("\n")
        os.chmod(tmp, stat.S_IMODE(manifest.stat().st_mode))
        os.replace(tmp, manifest)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
    print(f"Repaired manifest. Backup: {backup}")


if __name__ == "__main__":
    main()
