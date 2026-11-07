#!/usr/bin/env python3
"""Exercise the code swap and rollback only in a temporary active tree."""

import importlib.util
from pathlib import Path
import tempfile

CRATE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("color_deploy", CRATE / "deploy_wallpaper_color.py")
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)

with tempfile.TemporaryDirectory(prefix="nyvorel-color-deploy-") as directory:
    root = Path(directory)
    deploy.BACKUPS = root / "backups"
    deploy.STATE = root / "appearance-studio.json"
    deploy.FILES = {
        label: (source, root / "active" / target.relative_to(deploy.ACTIVE), marker)
        for label, (source, target, marker) in deploy.FILES.items()
    }
    originals = {}
    for label, (_, target, marker) in deploy.FILES.items():
        target.parent.mkdir(parents=True, exist_ok=True)
        content = ("previous " + (marker or "binary") + "\n").encode()
        target.write_bytes(content)
        target.chmod(0o755)
        originals[label] = content
    deploy.install()
    deploy.verify()
    snapshots = list(deploy.BACKUPS.glob("wallpaper-color-*"))
    assert len(snapshots) == 1 and (snapshots[0] / "rollback.sh").is_file()
    label = "nyvorel-appearance-studio"
    source, target, marker = deploy.FILES[label]
    replacement = root / "replacement-binary"
    replacement.write_bytes(source.read_bytes() + b"refresh")
    replacement.chmod(0o755)
    deploy.FILES[label] = (replacement, target, marker)
    deploy.refresh(snapshots[0])
    deploy.verify()
    deploy.restore(snapshots[0])
    for label, (_, target, _) in deploy.FILES.items():
        assert target.read_bytes() == originals[label]
    print("Isolated wallpaper color install and rollback passed")
