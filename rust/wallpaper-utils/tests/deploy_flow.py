#!/usr/bin/env python3
"""Verify installation and rollback without touching the live Quickshell tree."""

import importlib.util
from pathlib import Path
import tempfile

CRATE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("wallpaper_deploy", CRATE / "deploy_active.py")
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)


with tempfile.TemporaryDirectory(prefix="nyvorel-wallpaper-deploy-") as directory:
    root = Path(directory)
    deploy.BACKUPS = root / "backups"
    deploy.FILES = {
        name: (source, root / "active" / target.relative_to(deploy.ACTIVE), marker)
        for name, (source, target, marker) in deploy.FILES.items()
    }
    originals = {}
    for name, (_, target, marker) in deploy.FILES.items():
        if marker:
            target.parent.mkdir(parents=True, exist_ok=True)
            originals[name] = f"legacy {marker}\n".encode()
            target.write_bytes(originals[name])
    deploy.install()
    deploy.verify()
    snapshots = list(deploy.BACKUPS.glob("wallpaper-utils-*"))
    assert len(snapshots) == 1
    snapshot = snapshots[0]
    assert (snapshot / "rollback.sh").is_file()
    label = "Wallpapers.qml"
    source, target, marker = deploy.FILES[label]
    replacement = root / "replacement.qml"
    replacement.write_bytes(source.read_bytes() + b"\n// isolated refresh check\n")
    deploy.FILES[label] = (replacement, target, marker)
    deploy.refresh(snapshot)
    deploy.verify()
    assert target.read_bytes() == replacement.read_bytes()
    deploy.restore(snapshot, check_installed=True)
    for name, (_, target, _) in deploy.FILES.items():
        if name in originals:
            assert target.read_bytes() == originals[name]
        else:
            assert not target.exists()
    print("Isolated install and rollback passed")
