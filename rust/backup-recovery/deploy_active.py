#!/usr/bin/env python3
"""Deployment/rollback tool only; the installed Backup & Recovery runtime is Rust."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HOME = Path.home()
ACTIVE = HOME / ".config/quickshell/nyvorel"
HYPR = HOME / ".config/hypr"
BACKUPS = ROOT / ".migration-backups"
SOURCE = ROOT / "quickshell"
BINARY = ROOT / "rust/backup-recovery/target/release/nyvorel-backup-recovery"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def strip_block(text, start, end, label):
    pattern = re.compile(re.escape(start) + r".*?" + re.escape(end) + r"\n?", re.S)
    result, count = pattern.subn("", text)
    if count != 1:
        raise RuntimeError(f"{label}: expected one block, found {count}")
    return result


def edited_files():
    changes = {
        ACTIVE / "modules/nyvorel/backupRecovery/BackupRecoveryContent.qml":
            (SOURCE / "modules/nyvorel/backupRecovery/BackupRecoveryContent.qml").read_bytes(),
        ACTIVE / "modules/nyvorel/backupRecovery/BackupRecovery.qml":
            (SOURCE / "modules/nyvorel/backupRecovery/BackupRecovery.qml").read_bytes(),
        ACTIVE / "modules/nyvorel/regionSelector/ShellSurfacePolicy.qml":
            (SOURCE / "modules/nyvorel/regionSelector/ShellSurfacePolicy.qml").read_bytes(),
        ACTIVE / "scripts/backup-recovery/nyvorel-backup-recovery":
            (SOURCE / "scripts/backup-recovery/nyvorel-backup-recovery").read_bytes(),
        ACTIVE / "scripts/system/nyvorel-backup-recovery": BINARY.read_bytes(),
    }
    if b"python3" in changes[ACTIVE / "modules/nyvorel/backupRecovery/BackupRecoveryContent.qml"]:
        raise RuntimeError("QML still invokes Python")
    if not BINARY.is_file():
        raise RuntimeError("Build the Rust release binary before deployment")

    global_states = ACTIVE / "GlobalStates.qml"
    text = global_states.read_text()
    text = replace_once(text, '        "projects",\n', "", "exclusive surface list")
    text = replace_once(text, '        case "projects": return "Project Launcher"\n', "", "surface label")
    changes[global_states] = text.encode()

    family = ACTIVE / "panelFamilies/NyvorelFamily.qml"
    text = family.read_text()
    text = replace_once(text, "import qs.modules.nyvorel.projectLauncher\n", "", "family import")
    text = replace_once(text, "    PanelLoader { component: ProjectLauncher {} }\n", "", "family loader")
    changes[family] = text.encode()

    hyprland = HYPR / "hyprland.conf"
    text = strip_block(hyprland.read_text(),
        "# nyvorel-project-launcher-real-backdrop-v1 BEGIN\n",
        "# nyvorel-project-launcher-real-backdrop-v1 END",
        "Hyprland backdrop rule")
    changes[hyprland] = text.encode()

    rules = HYPR / "custom/rules.conf"
    text = strip_block(rules.read_text(),
        "# >>> project-command-center-layer >>>\n",
        "# <<< project-command-center-layer <<<",
        "Hyprland project layer")
    changes[rules] = text.encode()

    keybinds = HYPR / "custom/keybinds.conf"
    text = keybinds.read_text()
    old = text[text.index("# >>> nyvorel-project-launcher-native >>>"):]
    old = old[:old.index("# <<< nyvorel-project-launcher-native <<<") + len("# <<< nyvorel-project-launcher-native <<<")]
    text = replace_once(text, old,
        "##! Window management\nbind = Super+Alt, P, pin # Pin window to all workspaces",
        "project keybinds")
    changes[keybinds] = text.encode()

    base_keybinds = HYPR / "hyprland/keybinds.conf"
    text = replace_once(base_keybinds.read_text(),
        "bind = Super, P, pin # [hidden] Replaced by project command center",
        "bind = Super, P, pin # Pin window to all workspaces",
        "base pin keybind")
    changes[base_keybinds] = text.encode()

    for relative in ("custom/appearance-runtime.conf", "custom/appearance-runtime.lua"):
        path = HYPR / relative
        lines = [line for line in path.read_text().splitlines(keepends=True)
                 if "projectLauncher$" not in line]
        text = "".join(lines)
        text = text.replace("|projectLauncher", "")
        if "projectLauncher" in text:
            raise RuntimeError(f"Residual Project Launcher rule in {path}")
        changes[path] = text.encode()

    lua = HYPR / "hyprland.lua"
    lines = lua.read_text().splitlines(keepends=True)
    lines = [line for line in lines
             if "projectLauncher" not in line and "projectsToggle" not in line
             and 'hl.unbind("SUPER + P")' not in line]
    changes[lua] = "".join(lines).encode()

    return changes


def removed_files():
    return [
        ACTIVE / "modules/nyvorel/projectLauncher/ProjectLauncher.qml",
        ACTIVE / "modules/nyvorel/projectLauncher/nyvorel-projects.py",
        ACTIVE / "scripts/backup-recovery/control_center.py",
    ]


def atomic_write(path, data, mode):
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temp = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temp, mode)
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def verify(changes, removals):
    for path, expected in changes.items():
        if path.read_bytes() != expected:
            raise RuntimeError(f"Installed file differs: {path}")
    for path in removals:
        if path.exists():
            raise RuntimeError(f"Removed component still exists: {path}")
    for path in (ACTIVE / "GlobalStates.qml", ACTIVE / "panelFamilies/NyvorelFamily.qml",
                 ACTIVE / "modules/nyvorel/regionSelector/ShellSurfacePolicy.qml"):
        if b"projectLauncher" in path.read_bytes() or b'"projects"' in path.read_bytes():
            raise RuntimeError(f"Project Launcher reference remains: {path}")
    qml = (ACTIVE / "modules/nyvorel/backupRecovery/BackupRecoveryContent.qml").read_text()
    if "control_center.py" in qml or '"python3"' in qml:
        raise RuntimeError("Backup & Recovery still uses Python")


def deploy():
    changes = edited_files()
    removals = removed_files()
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    backup = BACKUPS / f"backup-recovery-rust-project-launcher-removal-{stamp}"
    backup.mkdir(parents=True, exist_ok=False)
    manifest = []
    for path in dict.fromkeys([*changes, *removals]):
        before = path.read_bytes() if path.exists() else None
        entry = {"path": str(path), "existed": before is not None,
                 "mode": (path.stat().st_mode & 0o777) if before is not None else None,
                 "sha256": digest(before) if before is not None else None}
        if before is not None:
            saved = backup / "files" / str(path).lstrip("/")
            saved.parent.mkdir(parents=True, exist_ok=True)
            saved.write_bytes(before)
        manifest.append(entry)
    (backup / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    rollback = backup / "rollback.sh"
    rollback.write_text(f"#!/bin/sh\nexec python3 {str(Path(__file__).resolve())!r} --rollback {str(backup)!r}\n")
    rollback.chmod(0o755)
    try:
        for path, data in changes.items():
            mode = 0o755 if path.name == "nyvorel-backup-recovery" else (
                path.stat().st_mode & 0o777 if path.exists() else 0o644)
            atomic_write(path, data, mode)
        for path in removals:
            path.unlink(missing_ok=True)
        (ACTIVE / "modules/nyvorel/projectLauncher").rmdir()
        verify(changes, removals)
    except Exception:
        restore(backup)
        raise
    print(backup)


def restore(backup):
    manifest = json.loads((backup / "manifest.json").read_text())
    for entry in manifest:
        path = Path(entry["path"])
        if entry["existed"]:
            data = (backup / "files" / str(path).lstrip("/")).read_bytes()
            if digest(data) != entry["sha256"]:
                raise RuntimeError(f"Backup checksum mismatch: {path}")
            atomic_write(path, data, entry["mode"])
        else:
            path.unlink(missing_ok=True)
    print(f"Restored {backup}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--rollback", type=Path)
    args = parser.parse_args()
    if args.rollback:
        restore(args.rollback.resolve())
    else:
        deploy()


if __name__ == "__main__":
    main()
