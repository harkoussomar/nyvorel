#!/usr/bin/env python3
"""Stage or roll back Arch Remote Rust fast paths in the active shell.

The QML caller, launcher, Rust binary, and staged Python controller can change.
State backups are private and are never restored over newer live state by code rollback.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]
CRATE = Path(__file__).resolve().parent
HOME = Path.home()
ACTIVE = HOME / ".config/quickshell/nyvorel"
QML = ACTIVE / "modules/nyvorel/archRemote/ArchRemoteContent.qml"
PYTHON = ACTIVE / "scripts/arch-remote/control_center.py"
LAUNCHER = ACTIVE / "scripts/arch-remote/nyvorel-arch-remote"
BINARY = ACTIVE / "scripts/system/nyvorel-arch-remote"
DEPLOYMENT_MANIFEST = HOME / ".local/state/nyvorel/arch-remote/deployment.json"
BACKUPS = ROOT / ".migration-backups"
OLD_CACHE = 'cachedSnapshotProc.command = ["python3", root.helperPath, "snapshot-cache"]'
NEW_CACHE = 'cachedSnapshotProc.command = [root.fastHelperPath, "snapshot-cache"]'
OLD_POLL = 'operationStatusProc.command = ["python3", root.helperPath, "operation-status"]'
NEW_POLL = 'operationStatusProc.command = [root.fastHelperPath, "operation-status"]'
NEW_PROPERTY = '    property string fastHelperPath: Quickshell.shellPath("scripts/arch-remote/nyvorel-arch-remote")\n'
OLD_PROPERTY = '    property string helperPath: Quickshell.shellPath("scripts/arch-remote/control_center.py")\n'
DATA = (
    HOME / ".local/state/nyvorel/arch-remote/runtime-state.json",
    HOME / ".local/state/nyvorel/arch-remote/activity.json",
    HOME / ".local/state/nyvorel/arch-remote/generation.json",
    HOME / ".cache/nyvorel/arch-remote/slow-state.json",
    HOME / ".cache/nyvorel/arch-remote/ssh-effective.json",
    Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}") / "arch-remote/operation.json",
)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def atomic_copy(source, destination, mode):
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".arch-remote-", dir=destination.parent)
    try:
        with os.fdopen(fd, "wb") as target:
            target.write(source.read_bytes())
            target.flush()
            os.fsync(target.fileno())
        os.chmod(name, mode)
        os.replace(name, destination)
        directory = os.open(destination.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def atomic_text(value, destination, mode):
    with tempfile.NamedTemporaryFile("w", dir=destination.parent, delete=False, encoding="utf-8") as stream:
        stream.write(value)
        stream.flush()
        os.fsync(stream.fileno())
        staging = Path(stream.name)
    try:
        os.chmod(staging, mode)
        os.replace(staging, destination)
    finally:
        staging.unlink(missing_ok=True)


def latest_backup():
    candidates = sorted(path for path in BACKUPS.glob("arch-remote-*")
                        if re.fullmatch(r"arch-remote-\d{8}-\d{6}", path.name)
                        and (path / "manifest.json").is_file())
    if not candidates:
        raise RuntimeError("No Arch Remote backup exists; run prepare first")
    path = candidates[-1]
    return path, json.loads((path / "manifest.json").read_text())


def latest_logs_backup():
    candidates = sorted(path for path in BACKUPS.glob("arch-remote-logs-*")
                        if re.fullmatch(r"arch-remote-logs-\d{8}-\d{6}", path.name)
                        and (path / "manifest.json").is_file()
                        and all((path / key).is_file() for key in ("qml", "launcher", "binary")))
    if not candidates:
        raise RuntimeError("No Arch Remote logs-stage backup exists; run prepare_logs first")
    path = candidates[-1]
    return path, json.loads((path / "manifest.json").read_text())


def latest_services_backup():
    candidates = sorted(path for path in BACKUPS.glob("arch-remote-services-*")
                        if re.fullmatch(r"arch-remote-services-\d{8}-\d{6}", path.name)
                        and all((path / key).is_file() for key in ("manifest.json", "python", "binary")))
    if not candidates:
        raise RuntimeError("No Arch Remote services-stage backup exists; run prepare_services first")
    path = candidates[-1]
    return path, json.loads((path / "manifest.json").read_text())


def latest_listeners_backup():
    candidates = sorted(path for path in BACKUPS.glob("arch-remote-listeners-*")
                        if re.fullmatch(r"arch-remote-listeners-\d{8}-\d{6}", path.name)
                        and all((path / key).is_file() for key in ("manifest.json", "python", "binary")))
    if not candidates:
        raise RuntimeError("No Arch Remote listeners-stage backup exists; run prepare_listeners first")
    path = candidates[-1]
    return path, json.loads((path / "manifest.json").read_text())


def latest_tailscale_backup():
    candidates = sorted(path for path in BACKUPS.glob("arch-remote-tailscale-*")
                        if re.fullmatch(r"arch-remote-tailscale-\d{8}-\d{6}", path.name)
                        and all((path / key).is_file() for key in ("manifest.json", "python", "binary")))
    if not candidates:
        raise RuntimeError("No Arch Remote Tailscale-stage backup exists; run prepare_tailscale first")
    path = candidates[-1]
    return path, json.loads((path / "manifest.json").read_text())


def latest_interfaces_backup():
    candidates = sorted(path for path in BACKUPS.glob("arch-remote-interfaces-*")
                        if re.fullmatch(r"arch-remote-interfaces-\d{8}-\d{6}", path.name)
                        and all((path / key).is_file() for key in ("manifest.json", "python", "binary")))
    if not candidates:
        raise RuntimeError("No Arch Remote interfaces-stage backup exists; run prepare_interfaces first")
    path = candidates[-1]
    return path, json.loads((path / "manifest.json").read_text())


def backup_key(path):
    if path.is_relative_to(HOME):
        return str(path.relative_to(HOME))
    return "runtime/" + path.name


def logs_key(path):
    return {QML: "qml", LAUNCHER: "launcher", BINARY: "binary"}[path]


def prepare():
    if not QML.is_file() or not PYTHON.is_file():
        raise RuntimeError("Active Arch Remote files are missing")
    current = QML.read_text()
    if any(current.count(pattern) != 1 for pattern in (OLD_PROPERTY, OLD_CACHE, OLD_POLL)):
        raise RuntimeError("Active QML does not match the pre-migration contract")
    BACKUPS.mkdir(mode=0o700, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    backup = BACKUPS / f"arch-remote-{stamp}"
    backup.mkdir(mode=0o700)
    os.chmod(backup, 0o700)
    manifest = {"version": 1, "created_at": stamp, "files": {}}
    for path in (QML, PYTHON, *DATA):
        if not path.is_file():
            continue
        key = backup_key(path)
        saved = backup / key
        atomic_copy(path, saved, 0o600)
        manifest["files"][key] = digest(saved)
    atomic_text(json.dumps(manifest, indent=2) + "\n", backup / "manifest.json", 0o600)
    print(f"Private Arch Remote backup: {backup}")


def migrated_qml(current):
    for old in (OLD_PROPERTY, OLD_CACHE, OLD_POLL):
        if current.count(old) != 1:
            raise RuntimeError(f"Unexpected active QML contract: {old}")
    return current.replace(OLD_PROPERTY, OLD_PROPERTY + NEW_PROPERTY).replace(OLD_CACHE, NEW_CACHE).replace(OLD_POLL, NEW_POLL)


def read_json(command):
    result = subprocess.run(command, text=True, capture_output=True, timeout=15, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    return json.loads(result.stdout)


def equivalent(left, right):
    if isinstance(left, dict) and isinstance(right, dict):
        return left.keys() == right.keys() and all(equivalent(left[key], right[key]) for key in left)
    if isinstance(left, list) and isinstance(right, list):
        return len(left) == len(right) and all(equivalent(a, b) for a, b in zip(left, right))
    if isinstance(left, float) and isinstance(right, float):
        # serde_json and Python can round persisted epoch fractions by one ULP.
        return math.isclose(left, right, rel_tol=0, abs_tol=0.000001)
    return type(left) is type(right) and left == right


def verify():
    rust_contract = read_json([str(LAUNCHER), "contract"])
    python_contract = read_json(["/usr/bin/python3", str(PYTHON), "contract"])
    if rust_contract != python_contract:
        raise RuntimeError("Active contract parity failed")
    rust_cache = read_json([str(LAUNCHER), "snapshot-cache"])
    python_cache = read_json(["/usr/bin/python3", str(PYTHON), "snapshot-cache"])
    if rust_cache.get("cache") and python_cache.get("cache"):
        rust_cache["cache"].pop("age_seconds", None)
        python_cache["cache"].pop("age_seconds", None)
    if not equivalent(rust_cache, python_cache):
        raise RuntimeError("Active cache parity failed")
    print("Active Arch Remote contract and cached-state parity: passed")


def install():
    backup, manifest = latest_backup()
    files = manifest["files"]
    for path in (QML, PYTHON):
        key = backup_key(path)
        if files.get(key) != digest(path):
            raise RuntimeError(f"Active {path.name} changed since backup; refusing install")
    if LAUNCHER.exists() or BINARY.exists():
        raise RuntimeError("Rust launcher or binary already exists; refusing overwrite")
    built = CRATE / "target/release/nyvorel-arch-remote"
    source_launcher = ROOT / "quickshell/scripts/arch-remote/nyvorel-arch-remote"
    if not built.is_file() or not source_launcher.is_file():
        raise RuntimeError("Build or launcher missing")
    migrated = migrated_qml(QML.read_text())
    source_qml = ROOT / "quickshell/modules/nyvorel/archRemote/ArchRemoteContent.qml"
    if migrated != source_qml.read_text():
        raise RuntimeError("Project QML differs from the active migration patch")
    try:
        atomic_copy(built, BINARY, 0o755)
        atomic_copy(source_launcher, LAUNCHER, 0o755)
        verify()
        atomic_text(migrated, QML, QML.stat().st_mode & 0o777)
    except Exception:
        BINARY.unlink(missing_ok=True)
        LAUNCHER.unlink(missing_ok=True)
        raise
    manifest["installed"] = {"qml_sha256": digest(QML), "binary_sha256": digest(BINARY),
                             "launcher_sha256": digest(LAUNCHER)}
    atomic_text(json.dumps(manifest, indent=2) + "\n", backup / "manifest.json", 0o600)
    print("Arch Remote Rust fast paths installed in the active shell")


def refresh_binary():
    backup, manifest = latest_backup()
    installed = manifest.get("installed") or {}
    if digest(QML) != installed.get("qml_sha256") or digest(LAUNCHER) != installed.get("launcher_sha256"):
        raise RuntimeError("Active Arch Remote integration changed; refusing binary refresh")
    if digest(BINARY) != installed.get("binary_sha256"):
        raise RuntimeError("Active Rust binary changed; refusing overwrite")
    built = CRATE / "target/release/nyvorel-arch-remote"
    saved = backup / "previous-installed-binary"
    atomic_copy(BINARY, saved, 0o600)
    try:
        atomic_copy(built, BINARY, 0o755)
        verify()
    except Exception:
        atomic_copy(saved, BINARY, 0o755)
        raise
    installed["binary_sha256"] = digest(BINARY)
    atomic_text(json.dumps(manifest, indent=2) + "\n", backup / "manifest.json", 0o600)
    print("Active Arch Remote Rust binary refreshed")


def prepare_logs():
    _, stage1 = latest_backup()
    installed = stage1.get("installed") or {}
    for path, key in ((QML, "qml_sha256"), (LAUNCHER, "launcher_sha256"), (BINARY, "binary_sha256")):
        if not path.is_file() or digest(path) != installed.get(key):
            raise RuntimeError(f"Stage 1 active {path.name} changed; refusing logs backup")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    backup = BACKUPS / f"arch-remote-logs-{stamp}"
    backup.mkdir(mode=0o700)
    os.chmod(backup, 0o700)
    manifest = {"version": 2, "created_at": stamp, "files": {}}
    for path in (QML, LAUNCHER, BINARY):
        key = logs_key(path)
        saved = backup / key
        atomic_copy(path, saved, 0o600)
        manifest["files"][key] = digest(saved)
    atomic_text(json.dumps(manifest, indent=2) + "\n", backup / "manifest.json", 0o600)
    print(f"Private Arch Remote logs-stage backup: {backup}")


def verify_logs():
    result = subprocess.run([sys.executable, str(CRATE / "tests/logs_parity.py"), str(LAUNCHER)],
                            text=True, capture_output=True, timeout=30, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    print(result.stdout.strip())


def install_logs():
    backup, manifest = latest_logs_backup()
    for path in (QML, LAUNCHER, BINARY):
        if digest(path) != manifest["files"].get(logs_key(path)):
            raise RuntimeError(f"Active {path.name} changed since logs backup; refusing install")
    old_qml = QML.read_text()
    old_command = 'logsProc.command = ["python3", root.helperPath, "logs", root.selectedLogService,'
    new_command = 'logsProc.command = [root.fastHelperPath, "logs", root.selectedLogService,'
    if old_qml.count(old_command) != 1:
        raise RuntimeError("Unexpected active logs command contract")
    migrated = old_qml.replace(old_command, new_command)
    if migrated != (ROOT / "quickshell/modules/nyvorel/archRemote/ArchRemoteContent.qml").read_text():
        raise RuntimeError("Project QML differs from logs migration patch")
    built = CRATE / "target/release/nyvorel-arch-remote"
    launcher = ROOT / "quickshell/scripts/arch-remote/nyvorel-arch-remote"
    if not built.is_file() or not launcher.is_file():
        raise RuntimeError("Logs-stage build or launcher missing")
    try:
        atomic_copy(built, BINARY, 0o755)
        atomic_copy(launcher, LAUNCHER, 0o755)
        verify()
        verify_logs()
        atomic_text(migrated, QML, QML.stat().st_mode & 0o777)
    except Exception:
        for path in (BINARY, LAUNCHER):
            atomic_copy(backup / logs_key(path), path, 0o755)
        raise
    manifest["installed"] = {logs_key(path): digest(path) for path in (QML, LAUNCHER, BINARY)}
    atomic_text(json.dumps(manifest, indent=2) + "\n", backup / "manifest.json", 0o600)
    print("Arch Remote Rust logs installed in the active shell")


def rollback_logs():
    backup, manifest = latest_logs_backup()
    installed = manifest.get("installed") or {}
    for path in (QML, LAUNCHER, BINARY):
        if not path.is_file() or digest(path) != installed.get(logs_key(path)):
            raise RuntimeError(f"Active {path.name} changed since logs install; refusing rollback")
    for path in (QML, LAUNCHER, BINARY):
        atomic_copy(backup / logs_key(path), path, 0o644 if path == QML else 0o755)
    print("Arch Remote logs stage rolled back to stage 1; live state was preserved.")


def prepare_services():
    _, stage1 = latest_backup()
    _, stage2 = latest_logs_backup()
    if digest(PYTHON) != stage1["files"].get(backup_key(PYTHON)):
        raise RuntimeError("Active Python controller changed since stage 1; refusing backup")
    for path in (QML, LAUNCHER, BINARY):
        if digest(path) != stage2.get("installed", {}).get(logs_key(path)):
            raise RuntimeError(f"Active {path.name} differs from stage 2; refusing backup")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    backup = BACKUPS / f"arch-remote-services-{stamp}"
    backup.mkdir(mode=0o700)
    os.chmod(backup, 0o700)
    manifest = {"version": 3, "created_at": stamp, "files": {}, "modes": {}}
    for path, key in ((PYTHON, "python"), (BINARY, "binary")):
        atomic_copy(path, backup / key, 0o600)
        manifest["files"][key] = digest(path)
        manifest["modes"][key] = path.stat().st_mode & 0o777
    atomic_text(json.dumps(manifest, indent=2) + "\n", backup / "manifest.json", 0o600)
    print(f"Private Arch Remote services-stage backup: {backup}")


def verify_services():
    result = subprocess.run([sys.executable, str(CRATE / "tests/services_parity.py"), str(BINARY), str(PYTHON)],
                            text=True, capture_output=True, timeout=30, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    print(result.stdout.strip())


def install_services():
    backup, manifest = latest_services_backup()
    if digest(PYTHON) != manifest["files"]["python"] or digest(BINARY) != manifest["files"]["binary"]:
        raise RuntimeError("Active Arch Remote files changed since services backup; refusing install")
    project_python = ROOT / "quickshell/scripts/arch-remote/control_center.py"
    built = CRATE / "target/release/nyvorel-arch-remote"
    if not project_python.is_file() or not built.is_file():
        raise RuntimeError("Services-stage sources or build missing")
    if "raw_services = snapshot_services_state()" not in project_python.read_text():
        raise RuntimeError("Project Python snapshot is not wired to the Rust collector")
    try:
        atomic_copy(built, BINARY, manifest["modes"]["binary"])
        atomic_copy(project_python, PYTHON, manifest["modes"]["python"])
        verify()
        verify_services()
    except Exception:
        atomic_copy(backup / "binary", BINARY, manifest["modes"]["binary"])
        atomic_copy(backup / "python", PYTHON, manifest["modes"]["python"])
        raise
    manifest["installed"] = {"python": digest(PYTHON), "binary": digest(BINARY)}
    atomic_text(json.dumps(manifest, indent=2) + "\n", backup / "manifest.json", 0o600)
    print("Arch Remote Rust service discovery installed in the active snapshot")


def rollback_services():
    backup, manifest = latest_services_backup()
    installed = manifest.get("installed") or {}
    for path, key in ((PYTHON, "python"), (BINARY, "binary")):
        if not path.is_file() or digest(path) != installed.get(key):
            raise RuntimeError(f"Active {path.name} changed since services install; refusing rollback")
    for path, key in ((PYTHON, "python"), (BINARY, "binary")):
        atomic_copy(backup / key, path, manifest["modes"][key])
    print("Arch Remote service collector rolled back to stage 2; live state was preserved.")


def prepare_listeners():
    _, stage3 = latest_services_backup()
    for path, key in ((PYTHON, "python"), (BINARY, "binary")):
        if digest(path) != stage3.get("installed", {}).get(key):
            raise RuntimeError(f"Active {path.name} differs from stage 3; refusing backup")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    backup = BACKUPS / f"arch-remote-listeners-{stamp}"
    backup.mkdir(mode=0o700)
    os.chmod(backup, 0o700)
    manifest = {"version": 4, "created_at": stamp, "files": {}, "modes": {}}
    for path, key in ((PYTHON, "python"), (BINARY, "binary")):
        atomic_copy(path, backup / key, 0o600)
        manifest["files"][key] = digest(path)
        manifest["modes"][key] = path.stat().st_mode & 0o777
    atomic_text(json.dumps(manifest, indent=2) + "\n", backup / "manifest.json", 0o600)
    print(f"Private Arch Remote listeners-stage backup: {backup}")


def verify_listeners():
    result = subprocess.run([sys.executable, str(CRATE / "tests/listeners_parity.py"), str(BINARY), str(PYTHON)],
                            text=True, capture_output=True, timeout=30, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    print(result.stdout.strip())


def install_listeners():
    backup, manifest = latest_listeners_backup()
    if digest(PYTHON) != manifest["files"]["python"] or digest(BINARY) != manifest["files"]["binary"]:
        raise RuntimeError("Active Arch Remote files changed since listeners backup; refusing install")
    project_python = ROOT / "quickshell/scripts/arch-remote/control_center.py"
    built = CRATE / "target/release/nyvorel-arch-remote"
    if not project_python.is_file() or not built.is_file():
        raise RuntimeError("Listeners-stage sources or build missing")
    if "listeners = snapshot_listeners_state(tailscale)" not in project_python.read_text():
        raise RuntimeError("Project Python snapshot is not wired to Rust listener enumeration")
    try:
        atomic_copy(built, BINARY, manifest["modes"]["binary"])
        atomic_copy(project_python, PYTHON, manifest["modes"]["python"])
        verify()
        verify_services()
        verify_listeners()
    except Exception:
        atomic_copy(backup / "binary", BINARY, manifest["modes"]["binary"])
        atomic_copy(backup / "python", PYTHON, manifest["modes"]["python"])
        raise
    manifest["installed"] = {"python": digest(PYTHON), "binary": digest(BINARY)}
    atomic_text(json.dumps(manifest, indent=2) + "\n", backup / "manifest.json", 0o600)
    print("Arch Remote Rust listener discovery installed in the active snapshot")


def rollback_listeners():
    backup, manifest = latest_listeners_backup()
    installed = manifest.get("installed") or {}
    for path, key in ((PYTHON, "python"), (BINARY, "binary")):
        if not path.is_file() or digest(path) != installed.get(key):
            raise RuntimeError(f"Active {path.name} changed since listeners install; refusing rollback")
    for path, key in ((PYTHON, "python"), (BINARY, "binary")):
        atomic_copy(backup / key, path, manifest["modes"][key])
    print("Arch Remote listener collector rolled back to stage 3; live state was preserved.")


def prepare_tailscale():
    _, stage4 = latest_listeners_backup()
    for path, key in ((PYTHON, "python"), (BINARY, "binary")):
        if digest(path) != stage4.get("installed", {}).get(key):
            raise RuntimeError(f"Active {path.name} differs from stage 4; refusing backup")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    backup = BACKUPS / f"arch-remote-tailscale-{stamp}"
    backup.mkdir(mode=0o700)
    os.chmod(backup, 0o700)
    manifest = {"version": 5, "created_at": stamp, "files": {}, "modes": {}}
    for path, key in ((PYTHON, "python"), (BINARY, "binary")):
        atomic_copy(path, backup / key, 0o600)
        manifest["files"][key] = digest(path)
        manifest["modes"][key] = path.stat().st_mode & 0o777
    atomic_text(json.dumps(manifest, indent=2) + "\n", backup / "manifest.json", 0o600)
    print(f"Private Arch Remote Tailscale-stage backup: {backup}")


def verify_tailscale():
    result = subprocess.run([sys.executable, str(CRATE / "tests/tailscale_parity.py"), str(BINARY), str(PYTHON)],
                            text=True, capture_output=True, timeout=30, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    print(result.stdout.strip())


def install_tailscale():
    backup, manifest = latest_tailscale_backup()
    if digest(PYTHON) != manifest["files"]["python"] or digest(BINARY) != manifest["files"]["binary"]:
        raise RuntimeError("Active Arch Remote files changed since Tailscale backup; refusing install")
    project_python = ROOT / "quickshell/scripts/arch-remote/control_center.py"
    built = CRATE / "target/release/nyvorel-arch-remote"
    if not project_python.is_file() or not built.is_file():
        raise RuntimeError("Tailscale-stage sources or build missing")
    if "base = snapshot_tailscale_status()" not in project_python.read_text():
        raise RuntimeError("Project Python snapshot is not wired to Rust Tailscale status")
    try:
        atomic_copy(built, BINARY, manifest["modes"]["binary"])
        atomic_copy(project_python, PYTHON, manifest["modes"]["python"])
        verify()
        verify_services()
        verify_listeners()
        verify_tailscale()
        verify_logs()
    except Exception:
        atomic_copy(backup / "binary", BINARY, manifest["modes"]["binary"])
        atomic_copy(backup / "python", PYTHON, manifest["modes"]["python"])
        raise
    manifest["installed"] = {"python": digest(PYTHON), "binary": digest(BINARY)}
    atomic_text(json.dumps(manifest, indent=2) + "\n", backup / "manifest.json", 0o600)
    print("Arch Remote Rust Tailscale status installed in the active snapshot")


def rollback_tailscale():
    backup, manifest = latest_tailscale_backup()
    installed = manifest.get("installed") or {}
    for path, key in ((PYTHON, "python"), (BINARY, "binary")):
        if not path.is_file() or digest(path) != installed.get(key):
            raise RuntimeError(f"Active {path.name} changed since Tailscale install; refusing rollback")
    for path, key in ((PYTHON, "python"), (BINARY, "binary")):
        atomic_copy(backup / key, path, manifest["modes"][key])
    print("Arch Remote Tailscale collector rolled back to stage 4; live state was preserved.")


def prepare_interfaces():
    _, stage5 = latest_tailscale_backup()
    for path, key in ((PYTHON, "python"), (BINARY, "binary")):
        if digest(path) != stage5.get("installed", {}).get(key):
            raise RuntimeError(f"Active {path.name} differs from stage 5; refusing backup")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    backup = BACKUPS / f"arch-remote-interfaces-{stamp}"
    backup.mkdir(mode=0o700)
    os.chmod(backup, 0o700)
    manifest = {"version": 6, "created_at": stamp, "files": {}, "modes": {}}
    for path, key in ((PYTHON, "python"), (BINARY, "binary")):
        atomic_copy(path, backup / key, 0o600)
        manifest["files"][key] = digest(path)
        manifest["modes"][key] = path.stat().st_mode & 0o777
    atomic_text(json.dumps(manifest, indent=2) + "\n", backup / "manifest.json", 0o600)
    print(f"Private Arch Remote interfaces-stage backup: {backup}")


def verify_interfaces():
    result = subprocess.run([sys.executable, str(CRATE / "tests/interfaces_parity.py"), str(BINARY), str(PYTHON)],
                            text=True, capture_output=True, timeout=30, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    print(result.stdout.strip())


def install_interfaces():
    backup, manifest = latest_interfaces_backup()
    if digest(PYTHON) != manifest["files"]["python"] or digest(BINARY) != manifest["files"]["binary"]:
        raise RuntimeError("Active Arch Remote files changed since interfaces backup; refusing install")
    project_python = ROOT / "quickshell/scripts/arch-remote/control_center.py"
    built = CRATE / "target/release/nyvorel-arch-remote"
    if not project_python.is_file() or not built.is_file():
        raise RuntimeError("Interfaces-stage sources or build missing")
    if "interfaces = snapshot_interfaces_state()" not in project_python.read_text():
        raise RuntimeError("Project Python slow snapshot is not wired to Rust interfaces")
    try:
        atomic_copy(built, BINARY, manifest["modes"]["binary"])
        atomic_copy(project_python, PYTHON, manifest["modes"]["python"])
        verify()
        verify_services()
        verify_listeners()
        verify_tailscale()
        verify_interfaces()
        verify_logs()
    except Exception:
        atomic_copy(backup / "binary", BINARY, manifest["modes"]["binary"])
        atomic_copy(backup / "python", PYTHON, manifest["modes"]["python"])
        raise
    manifest["installed"] = {"python": digest(PYTHON), "binary": digest(BINARY)}
    atomic_text(json.dumps(manifest, indent=2) + "\n", backup / "manifest.json", 0o600)
    print("Arch Remote Rust interfaces installed in the active slow snapshot")


def rollback_interfaces():
    backup, manifest = latest_interfaces_backup()
    installed = manifest.get("installed") or {}
    for path, key in ((PYTHON, "python"), (BINARY, "binary")):
        if not path.is_file() or digest(path) != installed.get(key):
            raise RuntimeError(f"Active {path.name} changed since interfaces install; refusing rollback")
    for path, key in ((PYTHON, "python"), (BINARY, "binary")):
        atomic_copy(backup / key, path, manifest["modes"][key])
    print("Arch Remote interfaces collector rolled back to stage 5; live state was preserved.")


def latest_upgrade_backup(name):
    candidates = sorted(path for path in BACKUPS.glob(f"arch-remote-{name}-*")
                        if re.fullmatch(rf"arch-remote-{re.escape(name)}-\d{{8}}-\d{{6}}", path.name)
                        and all((path / key).is_file() for key in ("manifest.json", "python", "binary")))
    if not candidates:
        raise RuntimeError(f"No Arch Remote {name} backup exists; run prepare_{name} first")
    path = candidates[-1]
    return path, json.loads((path / "manifest.json").read_text())


def prepare_upgrade(name, version, previous):
    _, prior = previous
    for path, key in ((PYTHON, "python"), (BINARY, "binary")):
        if digest(path) != prior.get("installed", {}).get(key):
            raise RuntimeError(f"Active {path.name} differs from prior stage; refusing backup")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    backup = BACKUPS / f"arch-remote-{name}-{stamp}"
    backup.mkdir(mode=0o700)
    os.chmod(backup, 0o700)
    manifest = {"version": version, "created_at": stamp, "files": {}, "modes": {}}
    for path, key in ((PYTHON, "python"), (BINARY, "binary")):
        atomic_copy(path, backup / key, 0o600)
        manifest["files"][key] = digest(path)
        manifest["modes"][key] = path.stat().st_mode & 0o777
    atomic_text(json.dumps(manifest, indent=2) + "\n", backup / "manifest.json", 0o600)
    print(f"Private Arch Remote {name} backup: {backup}")


def install_upgrade(name, marker, verify_new):
    backup, manifest = latest_upgrade_backup(name)
    if digest(PYTHON) != manifest["files"]["python"] or digest(BINARY) != manifest["files"]["binary"]:
        raise RuntimeError("Active Arch Remote files changed since backup; refusing install")
    project_python = ROOT / "quickshell/scripts/arch-remote/control_center.py"
    built = CRATE / "target/release/nyvorel-arch-remote"
    if not project_python.is_file() or not built.is_file() or marker not in project_python.read_text():
        raise RuntimeError(f"{name} sources, build, or controller wiring missing")
    try:
        atomic_copy(built, BINARY, manifest["modes"]["binary"])
        atomic_copy(project_python, PYTHON, manifest["modes"]["python"])
        verify()
        verify_services()
        verify_listeners()
        verify_tailscale()
        verify_interfaces()
        verify_logs()
        verify_exposure()
        verify_serve_funnel()
        verify_domain()
        verify_host_graphical()
        verify_power()
        verify_ssh_evidence()
        verify_sshd_effective()
        if name != "hardening":
            verify_hardening()
        if name not in {"hardening", "integrity"}:
            verify_integrity()
        if name not in {"hardening", "integrity", "wayvnc-security"}:
            verify_wayvnc_security()
        if name not in {"hardening", "integrity", "wayvnc-security", "lan-share-security"}:
            verify_lan_share_security()
        if name not in {"hardening", "integrity", "wayvnc-security", "lan-share-security", "pair-support"}:
            verify_pair_support()
        if name not in {"hardening", "integrity", "wayvnc-security", "lan-share-security", "pair-support", "audit"}:
            verify_audit()
        if name not in {"hardening", "integrity", "wayvnc-security", "lan-share-security", "pair-support", "audit", "pairing-readiness"}:
            verify_pairing_readiness()
        if name not in {"hardening", "integrity", "wayvnc-security", "lan-share-security", "pair-support", "audit", "pairing-readiness", "phone-guide"}:
            verify_phone_guide()
        if name not in {"hardening", "integrity", "wayvnc-security", "lan-share-security", "pair-support", "audit", "pairing-readiness", "phone-guide", "activity"}:
            verify_activity()
        if name not in {"hardening", "integrity", "wayvnc-security", "lan-share-security", "pair-support", "audit", "pairing-readiness", "phone-guide", "activity", "live-derive"}:
            verify_live_derive()
        if name not in {"hardening", "integrity", "wayvnc-security", "lan-share-security", "pair-support", "audit", "pairing-readiness", "phone-guide", "activity", "live-derive", "reference"}:
            verify_reference()
        if name not in {"hardening", "integrity", "wayvnc-security", "lan-share-security", "pair-support", "audit", "pairing-readiness", "phone-guide", "activity", "live-derive", "reference", "pairing-create"}:
            verify_pairing_create()
        if name not in {"hardening", "integrity", "wayvnc-security", "lan-share-security", "pair-support", "audit", "pairing-readiness", "phone-guide", "activity", "live-derive", "reference", "pairing-create", "pairing-cancel"}:
            verify_pairing_cancel()
        if name not in {"hardening", "integrity", "wayvnc-security", "lan-share-security", "pair-support", "audit", "pairing-readiness", "phone-guide", "activity", "live-derive", "reference", "pairing-create", "pairing-cancel", "user-service-action"}:
            verify_user_service_action()
        verify_new()
    except Exception:
        atomic_copy(backup / "binary", BINARY, manifest["modes"]["binary"])
        atomic_copy(backup / "python", PYTHON, manifest["modes"]["python"])
        raise
    manifest["installed"] = {"python": digest(PYTHON), "binary": digest(BINARY)}
    atomic_text(json.dumps(manifest, indent=2) + "\n", backup / "manifest.json", 0o600)
    print(f"Arch Remote Rust {name} installed in the active snapshot")


def rollback_upgrade(name):
    backup, manifest = latest_upgrade_backup(name)
    installed = manifest.get("installed") or {}
    for path, key in ((PYTHON, "python"), (BINARY, "binary")):
        if not path.is_file() or digest(path) != installed.get(key):
            raise RuntimeError(f"Active {path.name} changed since {name} install; refusing rollback")
    inventory = None
    if (backup / "deployment-manifest-before-reconcile.json").exists():
        inventory = json.loads(DEPLOYMENT_MANIFEST.read_text(encoding="utf-8"))
        rows = [row for row in inventory.get("files", []) if row.get("path") == str(PYTHON)]
        if len(rows) != 1 or rows[0].get("sha256") != installed["python"]:
            raise RuntimeError("Controller inventory changed since install; refusing rollback")
    for path, key in ((PYTHON, "python"), (BINARY, "binary")):
        atomic_copy(backup / key, path, manifest["modes"][key])
    if inventory is not None:
        rows[0]["sha256"] = manifest["files"]["python"]
        atomic_text(json.dumps(inventory, indent=2) + "\n", DEPLOYMENT_MANIFEST,
                    DEPLOYMENT_MANIFEST.stat().st_mode & 0o777)
    print(f"Arch Remote {name} rolled back; live state was preserved.")


def reconcile_controller_integrity():
    """Record a verified Rust migration in the package inventory without blessing other drift."""
    for name in ("controller-completion", "system-service-action", "user-service-action", "pairing-cancel", "pairing-create", "reference", "live-derive", "activity", "phone-guide", "pairing-readiness", "audit", "pair-support", "lan-share-security", "wayvnc-security", "integrity", "hardening"):
        try:
            candidate, stage = latest_upgrade_backup(name)
        except RuntimeError:
            continue
        if stage.get("installed"):
            backup = candidate
            break
    else:
        raise RuntimeError("No installed Arch Remote stage can be reconciled")
    installed = stage.get("installed") or {}
    if not installed or digest(PYTHON) != installed.get("python") or digest(BINARY) != installed.get("binary"):
        raise RuntimeError("Active Arch Remote files differ from the latest verified install")
    _, logs_stage = latest_logs_backup()
    qml_hash = logs_stage.get("installed", {}).get("qml")
    if not qml_hash or digest(QML) != qml_hash:
        raise RuntimeError("Active Arch Remote QML differs from the verified logs install")
    payload = json.loads(DEPLOYMENT_MANIFEST.read_text(encoding="utf-8"))
    updates = {str(PYTHON): installed["python"], str(QML): qml_hash}
    rows = {path: [row for row in payload.get("files", []) if row.get("path") == path]
            for path in updates}
    if any(len(found) != 1 for found in rows.values()):
        raise RuntimeError("Deployment inventory has no unique Arch Remote controller and QML entries")
    pending = {path: value for path, value in updates.items() if rows[path][0].get("sha256") != value}
    if not pending:
        print("Arch Remote integrity entries are current")
        return
    inventory_backup = backup / "deployment-manifest-before-reconcile.json"
    if not inventory_backup.exists():
        atomic_copy(DEPLOYMENT_MANIFEST, inventory_backup, 0o600)
    for path, value in pending.items():
        rows[path][0]["sha256"] = value
    payload["arch_remote_rust_reconciled_at"] = datetime.now(timezone.utc).isoformat()
    atomic_text(json.dumps(payload, indent=2) + "\n", DEPLOYMENT_MANIFEST,
                DEPLOYMENT_MANIFEST.stat().st_mode & 0o777)
    print(f"Arch Remote migration inventory reconciled; prior manifest backed up in {backup}")


def prepare_exposure():
    prepare_upgrade("exposure", 7, latest_interfaces_backup())


def verify_exposure():
    result = subprocess.run([sys.executable, str(CRATE / "tests/exposure_parity.py"), str(BINARY), str(PYTHON)],
                            text=True, capture_output=True, timeout=30, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    print(result.stdout.strip())


def install_exposure():
    install_upgrade("exposure", "exposure = snapshot_exposure_state(listeners, tailscale)", verify_exposure)


def rollback_exposure():
    rollback_upgrade("exposure")


def prepare_serve_funnel():
    prepare_upgrade("serve-funnel", 8, latest_upgrade_backup("exposure"))


def verify_serve_funnel():
    result = subprocess.run([sys.executable, str(CRATE / "tests/serve_funnel_parity.py"), str(BINARY), str(PYTHON)],
                            text=True, capture_output=True, timeout=30, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    print(result.stdout.strip())


def install_serve_funnel():
    install_upgrade("serve-funnel", 'base["serve"], base["funnel"] = snapshot_serve_funnel(binary)', verify_serve_funnel)


def rollback_serve_funnel():
    rollback_upgrade("serve-funnel")


def prepare_domain():
    prepare_upgrade("domain", 9, latest_upgrade_backup("serve-funnel"))


def verify_domain():
    result = subprocess.run([sys.executable, str(CRATE / "tests/domain_parity.py"), str(BINARY), str(PYTHON)],
                            text=True, capture_output=True, timeout=30, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    print(result.stdout.strip())


def install_domain():
    install_upgrade("domain", "services = snapshot_service_domain(raw_services, tailscale, exposure, graphical, slow[\"ssh\"], wayvnc_security)", verify_domain)


def rollback_domain():
    rollback_upgrade("domain")


def prepare_host_graphical():
    prepare_upgrade("host-graphical", 10, latest_upgrade_backup("domain"))


def verify_host_graphical():
    result = subprocess.run([sys.executable, str(CRATE / "tests/host_graphical_parity.py"), str(BINARY), str(PYTHON)],
                            text=True, capture_output=True, timeout=30, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    print(result.stdout.strip())


def install_host_graphical():
    install_upgrade("host-graphical", "host, graphical = snapshot_host_graphical()", verify_host_graphical)


def rollback_host_graphical():
    rollback_upgrade("host-graphical")


def prepare_power():
    prepare_upgrade("power", 11, latest_upgrade_backup("host-graphical"))


def verify_power():
    result = subprocess.run([sys.executable, str(CRATE / "tests/power_parity.py"), str(BINARY), str(PYTHON)],
                            text=True, capture_output=True, timeout=30, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    print(result.stdout.strip())


def install_power():
    install_upgrade("power", "wake, linger, lid = snapshot_power_state(interfaces)", verify_power)


def rollback_power():
    rollback_upgrade("power")


def prepare_ssh_evidence():
    prepare_upgrade("ssh-evidence", 12, latest_upgrade_backup("power"))


def verify_ssh_evidence():
    result = subprocess.run([sys.executable, str(CRATE / "tests/ssh_evidence_parity.py"), str(BINARY), str(PYTHON)],
                            text=True, capture_output=True, timeout=30, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    print(result.stdout.strip())


def install_ssh_evidence():
    install_upgrade("ssh-evidence", "ssh_auth, ssh_fingerprint = snapshot_ssh_evidence()", verify_ssh_evidence)


def rollback_ssh_evidence():
    rollback_upgrade("ssh-evidence")


def prepare_sshd_effective():
    prepare_upgrade("sshd-effective", 13, latest_upgrade_backup("ssh-evidence"))


def verify_sshd_effective():
    result = subprocess.run([sys.executable, str(CRATE / "tests/sshd_effective_parity.py"), str(BINARY), str(PYTHON)],
                            text=True, capture_output=True, timeout=30, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    print(result.stdout.strip())


def install_sshd_effective():
    install_upgrade("sshd-effective", "attempt = snapshot_sshd_effective(False)", verify_sshd_effective)


def rollback_sshd_effective():
    rollback_upgrade("sshd-effective")


def prepare_hardening():
    prepare_upgrade("hardening", 14, latest_upgrade_backup("sshd-effective"))


def verify_hardening():
    result = subprocess.run([sys.executable, str(CRATE / "tests/hardening_parity.py"), str(BINARY), str(PYTHON)],
                            text=True, capture_output=True, timeout=30, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    print(result.stdout.strip())


def install_hardening():
    install_upgrade("hardening", "hardening = snapshot_user_service_hardening_posture()", verify_hardening)


def rollback_hardening():
    rollback_upgrade("hardening")


def prepare_integrity():
    prepare_upgrade("integrity", 15, latest_upgrade_backup("hardening"))


def verify_integrity():
    result = subprocess.run([sys.executable, str(CRATE / "tests/integrity_parity.py"), str(BINARY), str(PYTHON)],
                            text=True, capture_output=True, timeout=30, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    print(result.stdout.strip())


def install_integrity():
    install_upgrade("integrity", "deployment_integrity = snapshot_deployment_integrity_posture()", verify_integrity)
    try:
        reconcile_controller_integrity()
    except Exception:
        rollback_upgrade("integrity")
        raise


def rollback_integrity():
    rollback_upgrade("integrity")


def prepare_wayvnc_security():
    prepare_upgrade("wayvnc-security", 16, latest_upgrade_backup("integrity"))


def verify_wayvnc_security():
    result = subprocess.run([sys.executable, str(CRATE / "tests/wayvnc_security_parity.py"), str(BINARY), str(PYTHON)],
                            text=True, capture_output=True, timeout=30, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    print(result.stdout.strip())


def install_wayvnc_security():
    install_upgrade("wayvnc-security", "wayvnc_security = snapshot_wayvnc_security_posture()", verify_wayvnc_security)
    try:
        reconcile_controller_integrity()
    except Exception:
        rollback_upgrade("wayvnc-security")
        raise


def rollback_wayvnc_security():
    rollback_upgrade("wayvnc-security")


def prepare_lan_share_security():
    prepare_upgrade("lan-share-security", 17, latest_upgrade_backup("wayvnc-security"))


def verify_lan_share_security():
    result = subprocess.run([sys.executable, str(CRATE / "tests/lan_share_security_parity.py"), str(BINARY), str(PYTHON)],
                            text=True, capture_output=True, timeout=30, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    print(result.stdout.strip())


def install_lan_share_security():
    install_upgrade("lan-share-security", "share_security = snapshot_lan_share_security_posture()", verify_lan_share_security)
    try:
        reconcile_controller_integrity()
    except Exception:
        rollback_upgrade("lan-share-security")
        raise


def rollback_lan_share_security():
    rollback_upgrade("lan-share-security")


def prepare_pair_support():
    prepare_upgrade("pair-support", 18, latest_upgrade_backup("lan-share-security"))


def verify_pair_support():
    result = subprocess.run([sys.executable, str(CRATE / "tests/pair_support_parity.py"), str(BINARY), str(PYTHON)],
                            text=True, capture_output=True, timeout=30, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    print(result.stdout.strip())


def install_pair_support():
    install_upgrade("pair-support", "support = snapshot_pair_command_support()", verify_pair_support)
    try:
        reconcile_controller_integrity()
    except Exception:
        rollback_upgrade("pair-support")
        raise


def rollback_pair_support():
    rollback_upgrade("pair-support")


def prepare_audit():
    prepare_upgrade("audit", 19, latest_upgrade_backup("pair-support"))


def verify_audit():
    result = subprocess.run([sys.executable, str(CRATE / "tests/audit_parity.py"), str(BINARY), str(PYTHON)],
                            text=True, capture_output=True, timeout=30, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    print(result.stdout.strip())


def install_audit():
    install_upgrade("audit", "audit, health = snapshot_security_audit(raw_services, tailscale, exposure, slow,", verify_audit)
    try:
        reconcile_controller_integrity()
    except Exception:
        rollback_upgrade("audit")
        raise


def rollback_audit():
    rollback_upgrade("audit")


def prepare_pairing_readiness():
    prepare_upgrade("pairing-readiness", 20, latest_upgrade_backup("audit"))


def verify_pairing_readiness():
    result = subprocess.run([sys.executable, str(CRATE / "tests/pairing_readiness_parity.py"), str(BINARY), str(PYTHON)],
                            text=True, capture_output=True, timeout=30, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    print(result.stdout.strip())


def install_pairing_readiness():
    install_upgrade("pairing-readiness", "readiness = snapshot_private_share_pairing_readiness(state)", verify_pairing_readiness)
    try:
        reconcile_controller_integrity()
    except Exception:
        rollback_upgrade("pairing-readiness")
        raise


def rollback_pairing_readiness():
    rollback_upgrade("pairing-readiness")


def prepare_phone_guide():
    prepare_upgrade("phone-guide", 21, latest_upgrade_backup("pairing-readiness"))


def verify_phone_guide():
    result = subprocess.run([sys.executable, str(CRATE / "tests/phone_guide_parity.py"), str(BINARY), str(PYTHON)],
                            text=True, capture_output=True, timeout=30, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    print(result.stdout.strip())


def install_phone_guide():
    install_upgrade("phone-guide", "state[\"phone_guide\"] = snapshot_phone_guide(state, slow)", verify_phone_guide)
    try:
        reconcile_controller_integrity()
    except Exception:
        rollback_upgrade("phone-guide")
        raise


def rollback_phone_guide():
    rollback_upgrade("phone-guide")


def prepare_activity():
    prepare_upgrade("activity", 22, latest_upgrade_backup("phone-guide"))


def verify_activity():
    result = subprocess.run([sys.executable, str(CRATE / "tests/activity_parity.py"), str(BINARY), str(PYTHON)],
                            text=True, capture_output=True, timeout=30, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    print(result.stdout.strip())


def install_activity():
    install_upgrade("activity", "state[\"phone_guide\"], state[\"activity\"] = snapshot_phone_and_activity(state, slow)", verify_activity)
    try:
        reconcile_controller_integrity()
    except Exception:
        rollback_upgrade("activity")
        raise


def rollback_activity():
    rollback_upgrade("activity")


def prepare_live_derive():
    prepare_upgrade("live-derive", 23, latest_upgrade_backup("activity"))


def verify_live_derive():
    result = subprocess.run([sys.executable, str(CRATE / "tests/live_derive_parity.py"), str(BINARY), str(PYTHON)],
                            text=True, capture_output=True, timeout=30, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    print(result.stdout.strip())


def install_live_derive():
    install_upgrade("live-derive", "combined = snapshot_live_derive(checked, generation, raw_services, tailscale, listeners,", verify_live_derive)
    try:
        reconcile_controller_integrity()
    except Exception:
        rollback_upgrade("live-derive")
        raise


def rollback_live_derive():
    rollback_upgrade("live-derive")


def prepare_reference():
    prepare_upgrade("reference", 24, latest_upgrade_backup("live-derive"))


def verify_reference():
    result = subprocess.run([sys.executable, str(CRATE / "tests/reference_parity.py"), str(BINARY), str(PYTHON)],
                            text=True, capture_output=True, timeout=30, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    print(result.stdout.strip())


def install_reference():
    install_upgrade("reference", "return emit(snapshot_reference_model(snapshot(False)))", verify_reference)
    try:
        reconcile_controller_integrity()
    except Exception:
        rollback_upgrade("reference")
        raise


def rollback_reference():
    rollback_upgrade("reference")


def prepare_pairing_create():
    prepare_upgrade("pairing-create", 25, latest_upgrade_backup("reference"))


def verify_pairing_create():
    result = subprocess.run([sys.executable, str(CRATE / "tests/pairing_create_parity.py"), str(BINARY), str(PYTHON)],
                            text=True, capture_output=True, timeout=30, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    print(result.stdout.strip())


def install_pairing_create():
    install_upgrade("pairing-create", "if RUST_PAIRING_CREATE_BIN.is_file() and os.access(RUST_PAIRING_CREATE_BIN, os.X_OK):", verify_pairing_create)
    try:
        reconcile_controller_integrity()
    except Exception:
        rollback_upgrade("pairing-create")
        raise


def rollback_pairing_create():
    rollback_upgrade("pairing-create")


def prepare_pairing_cancel():
    prepare_upgrade("pairing-cancel", 26, latest_upgrade_backup("pairing-create"))


def verify_pairing_cancel():
    result = subprocess.run([sys.executable, str(CRATE / "tests/pairing_cancel_parity.py"), str(BINARY), str(PYTHON)],
                            text=True, capture_output=True, timeout=30, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    print(result.stdout.strip())


def install_pairing_cancel():
    install_upgrade("pairing-cancel", "if RUST_PAIRING_CANCEL_BIN.is_file() and os.access(RUST_PAIRING_CANCEL_BIN, os.X_OK):", verify_pairing_cancel)
    try:
        reconcile_controller_integrity()
    except Exception:
        rollback_upgrade("pairing-cancel")
        raise


def rollback_pairing_cancel():
    rollback_upgrade("pairing-cancel")


def prepare_user_service_action():
    prepare_upgrade("user-service-action", 27, latest_upgrade_backup("pairing-cancel"))


def verify_user_service_action():
    result = subprocess.run([sys.executable, str(CRATE / "tests/user_service_action_parity.py"), str(BINARY), str(PYTHON)],
                            text=True, capture_output=True, timeout=30, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    print(result.stdout.strip())


def install_user_service_action():
    install_upgrade("user-service-action", "if RUST_USER_SERVICE_ACTION_BIN.is_file() and os.access(RUST_USER_SERVICE_ACTION_BIN, os.X_OK):", verify_user_service_action)
    try:
        reconcile_controller_integrity()
    except Exception:
        rollback_upgrade("user-service-action")
        raise


def rollback_user_service_action():
    rollback_upgrade("user-service-action")


def prepare_system_service_action():
    prepare_upgrade("system-service-action", 28, latest_upgrade_backup("user-service-action"))


def verify_system_service_action():
    result = subprocess.run([sys.executable, str(CRATE / "tests/system_service_action_parity.py"), str(BINARY), str(PYTHON)],
                            text=True, capture_output=True, timeout=30, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    print(result.stdout.strip())


def install_system_service_action():
    install_upgrade("system-service-action", "if RUST_SYSTEM_SERVICE_ACTION_BIN.is_file() and os.access(RUST_SYSTEM_SERVICE_ACTION_BIN, os.X_OK):", verify_system_service_action)
    try:
        reconcile_controller_integrity()
    except Exception:
        rollback_upgrade("system-service-action")
        raise


def rollback_system_service_action():
    rollback_upgrade("system-service-action")


def prepare_controller_completion():
    prepare_upgrade("controller-completion", 29, latest_upgrade_backup("system-service-action"))


def verify_controller_completion():
    result = subprocess.run([sys.executable, str(CRATE / "tests/controller_completion.py"), str(BINARY)],
                            text=True, capture_output=True, timeout=30, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    print(result.stdout.strip())


def install_controller_completion():
    install_upgrade("controller-completion", "RUST_SNAPSHOT_BIN = RUST_SERVICES_BIN", verify_controller_completion)
    try:
        reconcile_controller_integrity()
    except Exception:
        rollback_upgrade("controller-completion")
        raise


def rollback_controller_completion():
    rollback_upgrade("controller-completion")


def rollback():
    backup, manifest = latest_backup()
    installed = manifest.get("installed") or {}
    if not installed or digest(QML) != installed.get("qml_sha256"):
        raise RuntimeError("Active QML changed since install; refusing rollback overwrite")
    for path, key in ((BINARY, "binary_sha256"), (LAUNCHER, "launcher_sha256")):
        if not path.is_file() or digest(path) != installed.get(key):
            raise RuntimeError(f"Installed {path.name} changed; refusing rollback overwrite")
    if digest(PYTHON) != manifest["files"][backup_key(PYTHON)]:
        raise RuntimeError("Active Python controller changed; refusing rollback overwrite")
    atomic_copy(backup / backup_key(QML), QML, 0o644)
    BINARY.unlink()
    LAUNCHER.unlink()
    print("Arch Remote code rolled back. Current service and pairing state were preserved.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("prepare", "install", "verify", "refresh_binary", "rollback",
                                           "prepare_logs", "install_logs", "verify_logs", "rollback_logs",
                                           "prepare_services", "install_services", "verify_services", "rollback_services",
                                           "prepare_listeners", "install_listeners", "verify_listeners", "rollback_listeners",
                                           "prepare_tailscale", "install_tailscale", "verify_tailscale", "rollback_tailscale",
                                           "prepare_interfaces", "install_interfaces", "verify_interfaces", "rollback_interfaces",
                                           "prepare_exposure", "install_exposure", "verify_exposure", "rollback_exposure",
                                           "prepare_serve_funnel", "install_serve_funnel", "verify_serve_funnel", "rollback_serve_funnel",
                                           "prepare_domain", "install_domain", "verify_domain", "rollback_domain",
                                           "prepare_host_graphical", "install_host_graphical", "verify_host_graphical", "rollback_host_graphical",
                                           "prepare_power", "install_power", "verify_power", "rollback_power",
                                           "prepare_ssh_evidence", "install_ssh_evidence", "verify_ssh_evidence", "rollback_ssh_evidence",
                                           "prepare_sshd_effective", "install_sshd_effective", "verify_sshd_effective", "rollback_sshd_effective",
                                           "prepare_hardening", "install_hardening", "verify_hardening", "rollback_hardening",
                                           "prepare_integrity", "install_integrity", "verify_integrity", "rollback_integrity",
                                           "prepare_wayvnc_security", "install_wayvnc_security", "verify_wayvnc_security", "rollback_wayvnc_security",
                                           "prepare_lan_share_security", "install_lan_share_security", "verify_lan_share_security", "rollback_lan_share_security",
                                           "prepare_pair_support", "install_pair_support", "verify_pair_support", "rollback_pair_support",
                                           "prepare_audit", "install_audit", "verify_audit", "rollback_audit",
                                           "prepare_pairing_readiness", "install_pairing_readiness", "verify_pairing_readiness", "rollback_pairing_readiness",
                                           "prepare_phone_guide", "install_phone_guide", "verify_phone_guide", "rollback_phone_guide",
                                           "prepare_activity", "install_activity", "verify_activity", "rollback_activity",
                                           "prepare_live_derive", "install_live_derive", "verify_live_derive", "rollback_live_derive",
                                           "prepare_reference", "install_reference", "verify_reference", "rollback_reference",
                                           "prepare_pairing_create", "install_pairing_create", "verify_pairing_create", "rollback_pairing_create",
                                           "prepare_pairing_cancel", "install_pairing_cancel", "verify_pairing_cancel", "rollback_pairing_cancel",
                                           "prepare_user_service_action", "install_user_service_action", "verify_user_service_action", "rollback_user_service_action",
                                           "prepare_system_service_action", "install_system_service_action", "verify_system_service_action", "rollback_system_service_action",
                                           "prepare_controller_completion", "install_controller_completion", "verify_controller_completion", "rollback_controller_completion",
                                           "reconcile_controller_integrity"))
    action = parser.parse_args().action
    globals()[action]()
