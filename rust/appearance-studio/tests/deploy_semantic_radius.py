#!/usr/bin/env python3
"""Exercise code-only install and rollback without touching the active shell."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile


SCRIPT = Path(__file__).resolve().parents[1] / "deploy_semantic_radius.py"
spec = importlib.util.spec_from_file_location("deploy_semantic_radius", SCRIPT)
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="deploy-semantic-radius-") as temporary:
        root = Path(temporary)
        source_binary = root / "source/binary"
        active_binary = root / "active/binary"
        source_qml = root / "source/InterfaceConfig.qml"
        active_qml = root / "active/InterfaceConfig.qml"
        for path in (source_binary, active_binary, source_qml, active_qml):
            path.parent.mkdir(parents=True, exist_ok=True)
        source_binary.write_bytes(b"new binary")
        active_binary.write_bytes(b"old binary")
        active_binary.chmod(0o755)
        source_qml.write_text("before\n" + deploy.NEW_CALL + "\nafter\n")
        active_qml.write_text("before\n" + deploy.OLD_CALL + "\nafter\n")
        deploy.FILES = {"binary": (source_binary, active_binary),
                        "InterfaceConfig.qml": (source_qml, active_qml)}
        deploy.BACKUPS = root / "backups"
        deploy.STATE = root / "state.json"
        deploy.install()
        deploy.verify()
        snapshot = next(deploy.BACKUPS.iterdir())
        assert active_binary.read_bytes() == b"new binary"
        assert active_qml.read_text() == source_qml.read_text()
        deploy.restore(snapshot)
        assert active_binary.read_bytes() == b"old binary"
        assert active_qml.read_text() == "before\n" + deploy.OLD_CALL + "\nafter\n"
    print("Semantic radius install and rollback passed in temporary files")


if __name__ == "__main__":
    main()
