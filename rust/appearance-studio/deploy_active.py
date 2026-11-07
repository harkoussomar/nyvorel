#!/usr/bin/env python3
"""Install or roll back the native backend in the active Hyprland shell.

This touches the QML caller, launcher, binary, and managed color-script branch.
User appearance data is never rewritten by installation or code rollback.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from datetime import datetime

ROOT = Path(__file__).resolve().parents[2]
CRATE = Path(__file__).resolve().parent
ACTIVE = Path.home() / ".config/quickshell/nyvorel"
BACKUP = ROOT / ".migration-backups/appearance-studio-20261103-203014"
QML = ACTIVE / "modules/appearanceStudio/AppearanceStudio.qml"
WRAPPER = ACTIVE / "scripts/appearance-studio/nyvorel-appearance-studio"
BINARY = ACTIVE / "scripts/system/nyvorel-appearance-studio"
SWITCHWALL = ACTIVE / "scripts/colors/switchwall.sh"
PROJECT_SWITCHWALL = ROOT / "quickshell/scripts/colors/switchwall.sh"
ORIGINAL_SWITCHWALL = BACKUP / "managed-color-switchwall-original.sh"
STATE = Path.home() / ".config/nyvorel/appearance-studio.json"
PYTHON = ACTIVE / "scripts/appearance-studio/appearance_studio.py"
OLD_PATH = 'property string managerPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/appearance-studio/appearance_studio.py`'
NEW_PATH = 'property string managerPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/appearance-studio/nyvorel-appearance-studio`'
OLD_PROGRAM = "property string managerPython: '/usr/bin/python3'"
NEW_PROGRAM = "property string managerPython: '/usr/bin/env'"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def atomic_copy(source, destination, mode=None):
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, name = tempfile.mkstemp(prefix=".nyvorel-appearance-", dir=destination.parent)
    try:
        with os.fdopen(descriptor, "wb") as output:
            output.write(source.read_bytes())
            output.flush()
            os.fsync(output.fileno())
        os.chmod(name, mode if mode is not None else source.stat().st_mode & 0o777)
        os.replace(name, destination)
        fd = os.open(destination.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def command_output(command):
    result = subprocess.run(command, capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise RuntimeError(f"{' '.join(map(str, command))} failed: {result.stderr or result.stdout}")
    return json.loads(result.stdout)


def verify():
    old = command_output(["/usr/bin/python3", str(PYTHON), "status"])
    new = command_output([str(WRAPPER), "status"])
    if old != new:
        raise RuntimeError("Installed Rust status differs from the active Python contract")
    print("Active Appearance Studio status parity: passed")


def rollback():
    saved_qml = BACKUP / QML.relative_to(Path.home())
    saved_python = BACKUP / PYTHON.relative_to(Path.home())
    if not saved_qml.is_file() or not saved_python.is_file():
        raise RuntimeError("Code backup is missing; refusing incomplete rollback")
    current = QML.read_text()
    if NEW_PATH not in current or NEW_PROGRAM not in current:
        raise RuntimeError("Active QML changed since migration; refusing to overwrite it")
    expected_python = ROOT / "quickshell/scripts/appearance-studio/appearance_studio.py"
    if digest(PYTHON) not in {digest(saved_python), digest(expected_python)}:
        raise RuntimeError("Active Python controller changed since migration; refusing to overwrite it")
    if ORIGINAL_SWITCHWALL.is_file():
        if digest(SWITCHWALL) not in {digest(ORIGINAL_SWITCHWALL), digest(PROJECT_SWITCHWALL)}:
            raise RuntimeError("Active switchwall.sh changed since migration; refusing to overwrite it")
        atomic_copy(ORIGINAL_SWITCHWALL, SWITCHWALL, 0o755)
    atomic_copy(saved_qml, QML)
    atomic_copy(saved_python, PYTHON)
    WRAPPER.unlink(missing_ok=True)
    BINARY.unlink(missing_ok=True)
    print("Appearance Studio code rolled back. Current theme and saved appearances were preserved.")


def install():
    saved_qml = BACKUP / QML.relative_to(Path.home())
    saved_python = BACKUP / PYTHON.relative_to(Path.home())
    if not saved_qml.is_file() or not saved_python.is_file():
        raise RuntimeError("Pre-migration backup is incomplete")
    if digest(QML) != digest(saved_qml) or digest(PYTHON) != digest(saved_python):
        raise RuntimeError("Active Appearance Studio changed after backup; refusing to overwrite it")
    if STATE.is_file() and json.loads(STATE.read_text()).get("preview"):
        raise RuntimeError("A preview is active; keep or revert it before installation")
    built = CRATE / "target/release/nyvorel-appearance-studio"
    launcher = ROOT / "quickshell/scripts/appearance-studio/nyvorel-appearance-studio"
    if not built.is_file() or not launcher.is_file():
        raise RuntimeError("Build or launcher is missing")
    current = QML.read_text()
    if current.count(OLD_PATH) != 1 or current.count(OLD_PROGRAM) != 1:
        raise RuntimeError("Unexpected active QML command contract")
    migrated = current.replace(OLD_PATH, NEW_PATH).replace(OLD_PROGRAM, NEW_PROGRAM)
    atomic_copy(built, BINARY, 0o755)
    atomic_copy(launcher, WRAPPER, 0o755)
    with tempfile.NamedTemporaryFile("w", dir=QML.parent, delete=False) as output:
        staging = Path(output.name)
        output.write(migrated)
        output.flush()
        os.fsync(output.fileno())
    try:
        os.chmod(staging, QML.stat().st_mode & 0o777)
        os.replace(staging, QML)
        verify()
    except Exception:
        rollback()
        raise
    finally:
        staging.unlink(missing_ok=True)
    print("Appearance Studio stage 1 installed in the active Hyprland shell")


def upgrade():
    current = QML.read_text()
    if NEW_PATH not in current or NEW_PROGRAM not in current:
        raise RuntimeError("Active shell is not using the staged Appearance Studio launcher")
    if not BINARY.is_file():
        raise RuntimeError("Current Rust binary is missing")
    if STATE.is_file() and json.loads(STATE.read_text()).get("preview"):
        raise RuntimeError("A preview is active; keep or revert it before upgrading")
    built = CRATE / "target/release/nyvorel-appearance-studio"
    launcher = ROOT / "quickshell/scripts/appearance-studio/nyvorel-appearance-studio"
    if not built.is_file() or not launcher.is_file() or not WRAPPER.is_file():
        raise RuntimeError("Built backend or launcher is missing")
    if not PROJECT_SWITCHWALL.is_file() or not SWITCHWALL.is_file():
        raise RuntimeError("Theme color script is missing")
    if ORIGINAL_SWITCHWALL.is_file():
        if digest(SWITCHWALL) not in {digest(ORIGINAL_SWITCHWALL), digest(PROJECT_SWITCHWALL)}:
            raise RuntimeError("Active color script changed unexpectedly")
    elif digest(SWITCHWALL) == digest(PROJECT_SWITCHWALL):
        raise RuntimeError("Managed color script is already installed without a rollback backup")
    restore = BACKUP / "before-native-final"
    restore.mkdir(parents=True, exist_ok=True)
    for source, name in ((BINARY, "binary"), (WRAPPER, "launcher"),
                         (SWITCHWALL, "switchwall.sh")):
        atomic_copy(source, restore / name, 0o755)
    current = BACKUP / ("active-before-native-" + datetime.now().strftime("%Y%m%d-%H%M%S"))
    current.mkdir(parents=True, exist_ok=False)
    for source, name in ((QML, "AppearanceStudio.qml"), (PYTHON, "appearance_studio.py"),
                         (SWITCHWALL, "switchwall.sh"),
                         (STATE, "appearance-studio.json"),
                         (Path.home() / ".config/nyvorel/config.json", "config.json"),
                         (Path.home() / ".local/state/quickshell/user/generated/colors.json", "colors.json")):
        if source.is_file():
            atomic_copy(source, current / name)
    try:
        if not ORIGINAL_SWITCHWALL.is_file():
            atomic_copy(SWITCHWALL, ORIGINAL_SWITCHWALL, 0o755)
        atomic_copy(built, BINARY, 0o755)
        atomic_copy(launcher, WRAPPER, 0o755)
        atomic_copy(PROJECT_SWITCHWALL, SWITCHWALL, 0o755)
        verify()
        color_probe = subprocess.run(
            [str(BINARY), "__material-scss", "--color", "#A06D2C", "--mode", "dark",
             "--scheme", "scheme-tonal-spot", "--termscheme",
             str(ACTIVE / "scripts/colors/terminal/scheme-base.json"), "--blend_bg_fg"],
            capture_output=True, text=True, timeout=30,
        )
        if color_probe.returncode or "$term15: #" not in color_probe.stdout:
            raise RuntimeError("Installed Rust SCSS generator failed its smoke test")
    except Exception:
        atomic_copy(restore / "binary", BINARY, 0o755)
        atomic_copy(restore / "launcher", WRAPPER, 0o755)
        atomic_copy(restore / "switchwall.sh", SWITCHWALL, 0o755)
        raise
    print(f"Native Appearance Studio installed; previous code and current data backed up in {current}")


def update_legacy():
    saved = BACKUP / PYTHON.relative_to(Path.home())
    source = ROOT / "quickshell/scripts/appearance-studio/appearance_studio.py"
    if digest(PYTHON) != digest(saved):
        raise RuntimeError("Active Python controller changed after backup; refusing to overwrite it")
    compile(source.read_text(), str(source), "exec")
    try:
        atomic_copy(source, PYTHON)
        verify()
    except Exception:
        atomic_copy(saved, PYTHON)
        raise
    print("Preview watchdog now uses a transient user timer when available")


def upgrade_legacy():
    source = ROOT / "quickshell/scripts/appearance-studio/appearance_studio.py"
    current = PYTHON.read_text()
    new_unit = 'f"--unit=nyvorel-appearance-preview-{token}-{revision}-{uuid.uuid4().hex[:8]}"'
    old_unit = 'f"--unit=nyvorel-appearance-preview-{token}-{revision}"'
    expected_previous = source.read_text().replace(new_unit, old_unit)
    if current != expected_previous:
        raise RuntimeError("Active Python controller changed unexpectedly; refusing upgrade")
    previous = BACKUP / "appearance_studio-timer-v1.py"
    atomic_copy(PYTHON, previous)
    try:
        atomic_copy(source, PYTHON)
        verify()
    except Exception:
        atomic_copy(previous, PYTHON)
        raise
    print("Both preview watchdog checks now receive unique transient timer units")


def upgrade_watchdog_backend():
    source = ROOT / "quickshell/scripts/appearance-studio/appearance_studio.py"
    new_block = '''    rust_launcher = NYVOREL_DIR / "scripts/appearance-studio/nyvorel-appearance-studio"
    backend = (
        [str(rust_launcher)]
        if rust_launcher.is_file() and os.access(rust_launcher, os.X_OK)
        else [sys.executable, str(Path(__file__).resolve())]
    )
    command = [
        *backend,
'''
    old_block = '''    command = [
        sys.executable,
        str(Path(__file__).resolve()),
'''
    staged = source.read_text()
    if staged.count(new_block) != 1 or PYTHON.read_text() != staged.replace(new_block, old_block):
        raise RuntimeError("Active Python controller changed unexpectedly; refusing watchdog upgrade")
    previous = BACKUP / "appearance_studio-before-rust-watchdog.py"
    atomic_copy(PYTHON, previous)
    try:
        atomic_copy(source, PYTHON)
        verify()
    except Exception:
        atomic_copy(previous, PYTHON)
        raise
    print("Preview timers now invoke the Rust recovery backend; previous controller backed up")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["install", "upgrade", "update-legacy", "upgrade-legacy", "upgrade-watchdog-backend", "verify", "rollback"])
    action = parser.parse_args().action
    {"install": install, "upgrade": upgrade, "update-legacy": update_legacy,
     "upgrade-legacy": upgrade_legacy,
     "upgrade-watchdog-backend": upgrade_watchdog_backend,
     "verify": verify, "rollback": rollback}[action]()
