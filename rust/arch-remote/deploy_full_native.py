#!/usr/bin/env python3
"""Deployment-only Arch Remote installer. Python is not used by the installed runtime."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess

from deploy_active import atomic_copy, atomic_text, digest

ROOT = Path(__file__).resolve().parents[2]
HOME = Path.home()
ACTIVE = HOME / ".config/quickshell/nyvorel"
BACKUPS = ROOT / ".migration-backups"
PATHS = {
    "qml": ACTIVE / "modules/nyvorel/archRemote/ArchRemoteContent.qml",
    "wrapper": ACTIVE / "modules/nyvorel/archRemote/ArchRemote.qml",
    "launcher": ACTIVE / "scripts/arch-remote/nyvorel-arch-remote",
    "binary": ACTIVE / "scripts/system/nyvorel-arch-remote",
    "cli": HOME / ".local/bin/arch-remote",
    "deployment": HOME / ".local/state/nyvorel/arch-remote/deployment.json",
}
SOURCES = {
    "qml": ROOT / "quickshell/modules/nyvorel/archRemote/ArchRemoteContent.qml",
    "wrapper": ROOT / "quickshell/modules/nyvorel/archRemote/ArchRemote.qml",
    "launcher": ROOT / "quickshell/scripts/arch-remote/nyvorel-arch-remote",
    "binary": ROOT / "rust/arch-remote/target/release/nyvorel-arch-remote",
    "cli": ROOT / "rust/arch-remote/arch-remote",
}


def command(*args, timeout=35):
    result = subprocess.run(args, text=True, capture_output=True, timeout=timeout, check=True)
    return result.stdout


def check_source():
    for key, path in SOURCES.items():
        if not path.is_file():
            raise RuntimeError(f"Missing source for {key}: {path}")
    qml = SOURCES["qml"].read_text()
    if "python3" in qml or "helperPath" in qml.replace("fastHelperPath", ""):
        raise RuntimeError("Arch Remote QML still refers to the Python controller")
    if qml.count('root.fastHelperPath, "snapshot"') != 1:
        raise RuntimeError("Native snapshot route missing from QML")
    wrapper = SOURCES["wrapper"].read_text()
    if 'screenAtCursor' not in wrapper or 'screen: Quickshell.screens.find' not in wrapper:
        raise RuntimeError("Arch Remote wrapper lacks pointer-based screen placement")
    launcher = SOURCES["launcher"].read_text()
    if "python3" in launcher or 'exec "$binary" "$@"' not in launcher:
        raise RuntimeError("Launcher does not exclusively execute Rust")
    cli = SOURCES["cli"].read_text()
    if "python3" in cli or ' cli "$@"' not in cli:
        raise RuntimeError("CLI does not exclusively execute Rust")
    command("/bin/sh", "-n", str(SOURCES["launcher"]))
    command("/bin/sh", "-n", str(SOURCES["cli"]))
    for key, path in PATHS.items():
        if not path.is_file():
            raise RuntimeError(f"Missing active {key}: {path}")


def reconcile_manifest():
    path = PATHS["deployment"]
    payload = json.loads(path.read_text())
    for key in ("qml", "wrapper", "cli"):
        target = str(PATHS[key])
        rows = [row for row in payload.get("files", []) if row.get("path") == target]
        if len(rows) != 1:
            raise RuntimeError(f"Deployment inventory must contain one {key} entry")
        rows[0]["sha256"] = digest(PATHS[key])
    payload["arch_remote_full_native_at"] = datetime.now(timezone.utc).isoformat()
    atomic_text(json.dumps(payload, indent=2) + "\n", path, 0o600)


def verify():
    qml = PATHS["qml"].read_text()
    if "python3" in qml or "control_center.py" in qml:
        raise RuntimeError("Active Arch Remote QML still invokes Python")
    if PATHS["wrapper"].read_bytes() != SOURCES["wrapper"].read_bytes():
        raise RuntimeError("Active Arch Remote display placement differs from source")
    if PATHS["launcher"].read_bytes() != SOURCES["launcher"].read_bytes():
        raise RuntimeError("Active Arch Remote launcher differs from native source")
    if PATHS["cli"].read_bytes() != SOURCES["cli"].read_bytes():
        raise RuntimeError("Active arch-remote CLI differs from native source")
    if PATHS["binary"].read_bytes() != SOURCES["binary"].read_bytes():
        raise RuntimeError("Active Rust binary differs from native build")
    launcher = str(PATHS["launcher"])
    contract = json.loads(command(launcher, "contract"))
    if contract.get("ui_contract") != "2.4.1" or not contract.get("ok"):
        raise RuntimeError("Native controller contract failed")
    selftest = json.loads(command(launcher, "selftest"))
    if selftest.get("ok") is not True or selftest.get("scenario_count", 0) < 8:
        raise RuntimeError("Native controller degraded-state simulations failed")
    snapshot = json.loads(command(launcher, "snapshot", "--full", timeout=45))
    if snapshot.get("error") or snapshot.get("schema_version") != 2:
        raise RuntimeError("Native controller live snapshot failed")
    reference = json.loads(command(launcher, "reference", timeout=45))
    if reference.get("ok") is not True:
        raise RuntimeError("Native controller reference failed")
    invalid = json.loads(command(launcher, "operation-start", "service", "unknown", "start"))
    if invalid.get("error") is not True:
        raise RuntimeError("Native operation allowlist failed")
    cli = command(str(PATHS["cli"]), "status", timeout=45)
    if "ARCH REMOTE STATUS" not in cli:
        raise RuntimeError("User-facing native CLI failed")
    integrity = json.loads(command(launcher, "integrity"))
    if integrity.get("ok") is not True:
        raise RuntimeError(f"Deployment integrity check failed: {integrity.get('reason', 'unknown')}")
    print(f"Full native Arch Remote verified: schema {snapshot['schema_version']}, "
          f"generation {snapshot['generation']}, {selftest['scenario_count']} simulations")


def backup():
    check_source()
    BACKUPS.mkdir(mode=0o700, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    folder = BACKUPS / f"arch-remote-full-native-{stamp}"
    folder.mkdir(mode=0o700)
    manifest = {"stage": "full-native", "created_at": stamp, "original": {}, "modes": {}}
    for key, path in PATHS.items():
        mode = path.stat().st_mode & 0o777
        atomic_copy(path, folder / key, 0o600)
        manifest["original"][key] = digest(path)
        manifest["modes"][key] = mode
    atomic_text(json.dumps(manifest, indent=2) + "\n", folder / "manifest.json", 0o600)
    return folder, manifest


def restore(folder, manifest):
    for key, path in PATHS.items():
        atomic_copy(folder / key, path, manifest["modes"][key])


def install():
    folder, manifest = backup()
    print(f"Private rollback backup: {folder}")
    try:
        for key, source in SOURCES.items():
            atomic_copy(source, PATHS[key], manifest["modes"][key])
        reconcile_manifest()
        verify()
        manifest["installed"] = {key: digest(path) for key, path in PATHS.items()}
        atomic_text(json.dumps(manifest, indent=2) + "\n", folder / "manifest.json", 0o600)
    except Exception:
        restore(folder, manifest)
        raise
    print("Arch Remote full native controller installed; Python retained only for rollback")


def rollback():
    candidates = sorted(path for path in BACKUPS.glob("arch-remote-full-native-*")
                        if re.fullmatch(r"arch-remote-full-native-\d{8}-\d{6}", path.name)
                        and (path / "manifest.json").is_file())
    if not candidates:
        raise RuntimeError("No full-native rollback backup exists")
    folder = candidates[-1]
    manifest = json.loads((folder / "manifest.json").read_text())
    installed = manifest.get("installed") or {}
    if not installed or any(digest(path) != installed.get(key) for key, path in PATHS.items()):
        raise RuntimeError("Active files changed after this install; refusing overwrite")
    restore(folder, manifest)
    print("Arch Remote controller rolled back; live state and services were preserved")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("install", "verify", "rollback"))
    action = parser.parse_args().action
    globals()[action]()
