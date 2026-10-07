#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
pass(){ printf 'PASS  %s\n' "$*"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

HOME_SANDBOX="$TMP/home"
mkdir -p "$HOME_SANDBOX"

./install.sh \
  --target-home "$HOME_SANDBOX" \
  --yes \
  --no-activate >"$TMP/install.log"

CLI="$HOME_SANDBOX/.local/bin/nyvorel"
[[ -x "$CLI" ]] || die "installed nyvorel CLI missing"

echo "== Clean standard doctor =="
"$CLI" doctor \
  --home "$HOME_SANDBOX" \
  --no-session \
  --json >"$TMP/clean.json"

python3 - "$TMP/clean.json" <<'PY'
from pathlib import Path
import json
import sys

data = json.loads(Path(sys.argv[1]).read_text())

assert data["schema"] == 1
assert data["product"] == "Nyvorel"
assert data["result"] in {"PASS", "WARN"}
assert data["summary"]["FAIL"] == 0

checks = {item["id"]: item for item in data["checks"]}

for check_id in (
    "install.core",
    "install.systemd-files",
    "manifest.state",
    "manifest.contract",
    "manifest.integrity",
    "install.materialization",
):
    assert checks[check_id]["status"] == "PASS", (check_id, checks[check_id])

assert checks["session.environment"]["status"] == "SKIP"
assert checks["session.systemd"]["status"] == "SKIP"
assert checks["session.hyprland"]["status"] == "SKIP"
PY

echo "== Deep drift detection =="
printf '\nci-doctor-intentional-edit\n' \
  >>"$HOME_SANDBOX/.config/quickshell/nyvorel/shell.qml"

"$CLI" doctor \
  --home "$HOME_SANDBOX" \
  --no-session \
  --deep \
  --json >"$TMP/drift.json"

python3 - "$TMP/drift.json" <<'PY'
from pathlib import Path
import json
import sys

data = json.loads(Path(sys.argv[1]).read_text())
checks = {item["id"]: item for item in data["checks"]}

assert data["summary"]["FAIL"] == 0
assert checks["manifest.integrity"]["status"] == "WARN"
assert ".config/quickshell/nyvorel/shell.qml" in checks["manifest.integrity"]["detail"]
PY

echo "== Missing-file failure =="
rm -f "$HOME_SANDBOX/.config/quickshell/nyvorel/shell.qml"

set +e
"$CLI" doctor \
  --home "$HOME_SANDBOX" \
  --no-session \
  --deep \
  --json >"$TMP/missing.json"
MISSING_CODE=$?
set -e

[[ "$MISSING_CODE" == "1" ]] \
  || die "doctor should exit 1 for missing critical managed file, got $MISSING_CODE"

python3 - "$TMP/missing.json" <<'PY'
from pathlib import Path
import json
import sys

data = json.loads(Path(sys.argv[1]).read_text())
checks = {item["id"]: item for item in data["checks"]}

assert data["result"] == "FAIL"
assert data["summary"]["FAIL"] >= 1
assert checks["install.core"]["status"] == "FAIL"
assert checks["manifest.integrity"]["status"] == "FAIL"
PY

echo "== Strict warning policy =="
set +e
"$CLI" doctor \
  --home "$HOME_SANDBOX" \
  --no-session \
  --strict \
  --json >"$TMP/strict.json"
STRICT_CODE=$?
set -e

[[ "$STRICT_CODE" == "1" ]] \
  || die "strict doctor should return non-zero with warnings/failures"

pass "doctor clean state, deep drift, missing-file, JSON, and strict behavior"
