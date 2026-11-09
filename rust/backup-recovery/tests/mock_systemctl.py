#!/usr/bin/env python3
"""Exercise the native controller without starting real backup services."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / "target/release/nyvorel-backup-recovery"


def call(env, *args):
    result = subprocess.run([BINARY, *args], env=env, text=True, capture_output=True, check=True)
    assert result.stderr == "", result.stderr
    return json.loads(result.stdout)


def main():
    with tempfile.TemporaryDirectory(prefix="backup-recovery-test-") as temp:
        root = Path(temp)
        mock = root / "systemctl"
        mock.write_text("""#!/bin/sh
case "$1" in
  show)
    case " $* " in
      *" --value "*)
        if [ "$TEST_MISSING_STATE" = 1 ]; then printf 'not-found\n';
        else printf 'loaded\n'; fi
        exit 0
        ;;
    esac
    for unit in "$@"; do
      case "$unit" in
        *.service)
          state=inactive
          if [ "$TEST_BUSY" = 1 ] && [ "$unit" = backup-recovery-backup.service ]; then state=active; fi
          printf 'Id=%s\\nLoadState=loaded\\nActiveState=%s\\nSubState=dead\\nResult=success\\nExecMainStatus=0\\n\\n' "$unit" "$state"
          ;;
      esac
    done
    ;;
  start)
    if [ -n "$TEST_START_LOG" ]; then printf '%s\n' "$*" >> "$TEST_START_LOG"; fi
    if [ "$TEST_REJECT" = 1 ]; then echo 'rejected by mock' >&2; exit 1; fi
    ;;
  *) exit 2 ;;
esac
""")
        mock.chmod(0o755)
        env = {**os.environ, "PATH": temp + os.pathsep + os.environ["PATH"], "HOME": temp}

        assert call(env, "ping")["version"] == "1.6.0"
        instant = call(env, "snapshot", "--instant")
        assert instant["snapshot_mode"] == "instant-cache"
        assert instant["schema_version"] == 2
        live = call(env, "snapshot")
        assert live["snapshot_mode"] == "fast-live"
        assert live["actions"]["backup"]["active_state"] == "inactive"

        assert call(env, "action", "backup")["accepted"] is True
        busy_env = {**env, "TEST_BUSY": "1"}
        busy = call(busy_env, "action", "eject")
        assert busy["error"] == "busy" and busy["current_action"] == "backup"
        rejected = call({**env, "TEST_REJECT": "1"}, "action", "backup")
        assert rejected["error"] == "action-rejected"
        assert call(env, "action", "nonsense")["error"] == "unknown-action"
        assert call(env, "action")["error"] == "missing-action"
        assert call(env, "nonsense")["error"] == "unknown-command"

        refreshed = call(env, "refresh")
        assert refreshed["refresh_ok"] is True
        assert refreshed["state_health"]["refresh_ok"] is True
        failed = call({**env, "TEST_REJECT": "1"}, "snapshot", "--refresh")
        assert failed["state_health"]["refresh_ok"] is False
        assert failed["refresh_error"] == "rejected by mock"
        start_log = root / "missing-state-starts.log"
        missing = call({**env, "TEST_MISSING_STATE": "1", "TEST_START_LOG": str(start_log)}, "snapshot", "--refresh")
        assert missing["state_health"]["refresh_ok"] is False
        assert "not installed" in missing["refresh_error"]
        assert not start_log.exists(), "missing service must not request authorization"
        print("mock systemctl: snapshot, refresh, busy, accept and reject passed")


if __name__ == "__main__":
    main()
