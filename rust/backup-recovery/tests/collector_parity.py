#!/usr/bin/env python3
"""Compare Rust and Python collectors on offline, cached-evidence fixtures."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
LEGACY = ROOT / "legacy/state_collector.py"
BINARY = ROOT / "target/release/nyvorel-backup-recovery-root"


def differences(left, right, prefix=""):
    if isinstance(left, dict) and isinstance(right, dict):
        for key in sorted(left.keys() | right.keys()):
            yield from differences(left.get(key), right.get(key), f"{prefix}.{key}")
    elif isinstance(left, list) and isinstance(right, list):
        if len(left) != len(right):
            yield f"{prefix}: length {len(left)} != {len(right)}"
        for index, (a, b) in enumerate(zip(left, right)):
            yield from differences(a, b, f"{prefix}[{index}]")
    elif left != right:
        yield f"{prefix}: {str(left)[:120]!r} != {str(right)[:120]!r}"


def fixture(root):
    state = root / "var/lib/backup-recovery"
    state.mkdir(parents=True)
    config = root / "etc/backup-recovery"
    config.mkdir(parents=True)
    backup = root / "mnt/backup"
    backup.mkdir(parents=True)
    password = root / "etc/restic/password"
    password.parent.mkdir(parents=True)
    password.write_text("test-only\n")
    uuid = "nyvorel-parity-nonexistent-uuid"
    (config / "config.json").write_text(json.dumps({
        "backup_uuid": uuid, "mountpoint": str(backup),
        "restic_repo": str(backup / "restic"), "restic_password_file": str(password),
        "restic_cache_dir": str(root / "var/cache/restic"), "user": os.environ["USER"],
        "restic_expected_hostname": "parity-host",
        "restic_required_tags": ["system"], "restic_required_paths": ["/etc"],
        "overdue_hours": 48, "timeshift_overdue_hours": 168,
    }))
    shutil.copy2("/etc/backup-recovery/install.json", config / "install.json")
    timeshift = root / "etc/timeshift"
    timeshift.mkdir(parents=True)
    shutil.copy2("/etc/timeshift/timeshift.json", timeshift / "timeshift.json")
    (root / "etc/.git").symlink_to("/etc/.git")
    snapshot_time = "2026-10-30T10:00:00+00:00"
    evidence = {
        "restic": {
            "known": True, "scope_version": 1, "repository_id": "parity-repo",
            "scope": {"hostname": "parity-host", "required_tags": ["system"], "required_paths": ["/etc"]},
            "snapshots": [{"id": "snapshot-1", "short_id": "snapshot", "time": snapshot_time}],
            "count": 1, "latest": {"id": "snapshot-1", "short_id": "snapshot", "time": snapshot_time},
            "verified_at": int(time.time()) - 3600,
        },
        "timeshift": {"known": True, "snapshots": [], "count": 0, "latest": None},
        "smart": {"known": True, "health": "passed", "condition": "healthy",
                  "attributes": {"reallocated": 0, "pending": 0, "uncorrectable": 0},
                  "historical_error_count": 0, "self_tests": []},
        "recovery": {"known": True, "guide_known": True, "manifests_known": True,
                     "manifests_updated_at": int(time.time()) - 3600, "iso_files": ["rescue.iso"]},
    }
    (state / "evidence.json").write_text(json.dumps(evidence))
    markers = {
        "restic-check-ok.json": {"ok": True, "time": int(time.time()) - 3600,
                                 "backup_uuid": uuid, "repository_id": "parity-repo", "snapshot_id": "snapshot-1"},
        "restore-test-ok.json": {"ok": True, "time": int(time.time()) - 3600,
                                 "backup_uuid": uuid, "repository_id": "parity-repo", "snapshot_id": "snapshot-1"},
        "credential-recovery.json": {"verified": True, "verified_at": int(time.time()) - 3600,
                                     "backup_uuid": uuid, "repository_id": "parity-repo", "label": "safe copy"},
        "recovery-media.json": {"verified": True, "verified_at": int(time.time()) - 3600,
                                "backup_uuid": uuid, "label": "USB"},
        "second-copy.json": {"verified": True, "verified_at": int(time.time()) - 3600,
                             "backup_uuid": uuid, "label": "offsite"},
        "backup-proof.json": {"ok": True, "time": int(time.time()) - 3600,
                              "backup_uuid": uuid, "repository_id": "parity-repo", "snapshot_id": "snapshot-1"},
        "restic-data-check.json": {"known": True, "ok": True, "time": int(time.time()) - 3600,
                                   "backup_uuid": uuid, "repository_id": "parity-repo",
                                   "subset": 2, "total_subsets": 4, "next_subset": 3},
    }
    for name, payload in markers.items():
        (state / name).write_text(json.dumps(payload))
    (state / "activity.json").write_text(json.dumps([
        {"time": int(time.time()) - 10, "title": "last"},
        {"time": int(time.time()) - 100, "title": "before"},
    ]))
    return state, config


def main():
    with tempfile.TemporaryDirectory(prefix="nyvorel-collector-parity-") as temp:
        root = Path(temp)
        state, config = fixture(root)
        spec = importlib.util.spec_from_file_location("legacy_collector", LEGACY)
        legacy = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(legacy)
        legacy.CONFIG_FILE = config / "config.json"
        legacy.INSTALL_FILE = config / "install.json"
        legacy.STATE_DIR = state
        legacy.STATE_FILE = state / "state.json"
        legacy.EVIDENCE_FILE = state / "evidence.json"
        legacy.ACTIVITY_FILE = state / "activity.json"
        for attr, name in [
            ("RESTIC_CHECK_MARKER", "restic-check-ok.json"),
            ("RESTIC_DATA_CHECK_MARKER", "restic-data-check.json"),
            ("RESTORE_TEST_MARKER", "restore-test-ok.json"),
            ("BACKUP_PROOF_MARKER", "backup-proof.json"),
            ("CREDENTIAL_EVIDENCE_MARKER", "credential-recovery.json"),
            ("RECOVERY_MEDIA_EVIDENCE_MARKER", "recovery-media.json"),
            ("SECOND_COPY_EVIDENCE_MARKER", "second-copy.json"),
        ]:
            setattr(legacy, attr, state / name)
        legacy.secure_user_readable_state = lambda *_: None
        legacy.collect_state_once()
        expected = json.loads((state / "state.json").read_text())
        result = subprocess.run([BINARY, "collect", "--dry-run"], text=True, capture_output=True,
                                env={**os.environ, "NYVOREL_BACKUP_TEST_ROOT": temp}, check=True)
        actual = json.loads(result.stdout)
        expected.pop("generated_at")
        actual.pop("generated_at")
        errors = list(differences(expected, actual))
        if errors:
            print("\n".join(errors[:50]))
            raise SystemExit(f"{len(errors)} collector parity differences")
        print("collector parity: cached offline state matches legacy output")


if __name__ == "__main__":
    main()
