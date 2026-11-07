#!/usr/bin/env python3
"""Check installation and rollback in a temporary Quickshell tree."""

import importlib.util
from pathlib import Path
import tempfile

CRATE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("keybind_deploy", CRATE / "deploy_active.py")
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)

with tempfile.TemporaryDirectory(prefix="nyvorel-keybind-deploy-") as directory:
    root = Path(directory)
    deploy.BACKUPS = root / "backups"
    deploy.FILES = {
        label: (source, root / "active" / target.relative_to(deploy.ACTIVE))
        for label, (source, target) in deploy.FILES.items()
    }
    qml = deploy.FILES["HyprlandKeybinds.qml"][1]
    qml.parent.mkdir(parents=True)
    qml.write_text("property string keybindParserPath: get_keybinds.py\n")
    qml.chmod(0o644)
    original = qml.read_bytes()
    deploy.install()
    deploy.verify()
    snapshots = list(deploy.BACKUPS.glob("keybinds-*"))
    assert len(snapshots) == 1 and (snapshots[0] / "rollback.sh").is_file()
    deploy.restore(snapshots[0])
    assert qml.read_bytes() == original
    assert qml.stat().st_mode & 0o777 == 0o644
    assert not deploy.FILES["nyvorel-keybinds"][1].exists()
    print("Isolated keybind install and rollback passed")
