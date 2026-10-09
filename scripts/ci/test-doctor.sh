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

assert checks["dependencies.contract"]["status"] == "PASS"
assert checks["dependencies.required"]["status"] == "SKIP"
assert checks["dependencies.optional"]["status"] == "SKIP"
assert data["dependency_checks"] is False
assert data["dependencies"]["contract"]["status"] == "PASS"

assert checks["session.environment"]["status"] == "SKIP"
assert checks["session.systemd"]["status"] == "SKIP"
assert checks["session.hyprland"]["status"] == "SKIP"
PY

echo "== Dependency preflight contract =="
DOCTOR="$HOME_SANDBOX/.local/bin/nyvorel-doctor"
CONTRACT="$HOME_SANDBOX/.local/share/nyvorel/dependencies/arch.json"

[[ -x "$DOCTOR" ]] || die "installed doctor missing"
[[ -s "$CONTRACT" ]] || die "installed dependency contract missing"

FAKE_BIN="$TMP/dependency-path"
mkdir -p "$FAKE_BIN"

REAL_PYTHON="$(command -v python3)"
ln -s "$REAL_PYTHON" "$FAKE_BIN/python3"

python3 - "$CONTRACT" <<'PYDEPS' >"$TMP/required-commands.txt"
from pathlib import Path
import json
import sys

data = json.loads(Path(sys.argv[1]).read_text())
for entry in data["required"]:
    file_key = next((key for key in ("files_any_of", "files_all_of") if key in entry), None)
    if file_key:
        fixture = Path(sys.argv[1]).parent / (entry["id"] + ".fixture")
        fixture.write_text("test runtime asset\n")
        entry[file_key] = [str(fixture)]
        continue
    if isinstance(entry.get("commands_all_of"), list):
        commands = entry["commands_all_of"]
        for command in commands:
            print(command)
    else:
        commands = entry["commands_any_of"]
        print(commands[0])
Path(sys.argv[1]).write_text(json.dumps(data))
PYDEPS

while IFS= read -r command; do
  [[ -n "$command" ]] || continue
  [[ "$command" == "python3" ]] && continue
  ln -sf /bin/true "$FAKE_BIN/$command"
done <"$TMP/required-commands.txt"

# These are explicit color-runtime fixtures, not a claim that the source
# installer provisions a Python environment.
mkdir -p "$HOME_SANDBOX/.config/matugen" "$HOME_SANDBOX/.local/state/quickshell/.venv/bin"
printf '[templates.fixture]\ninput_path = "template.txt"\n' > "$HOME_SANDBOX/.config/matugen/config.toml"
printf 'synthetic template\n' > "$HOME_SANDBOX/.config/matugen/template.txt"
ln -s /bin/true "$HOME_SANDBOX/.local/state/quickshell/.venv/bin/python"

PATH="$FAKE_BIN" "$DOCTOR" \
  --home "$HOME_SANDBOX" \
  --no-session \
  --dependencies \
  --json >"$TMP/dependencies-ok.json"

python3 - "$TMP/dependencies-ok.json" <<'PYDEPS'
from pathlib import Path
import json
import sys

data = json.loads(Path(sys.argv[1]).read_text())
checks = {item["id"]: item for item in data["checks"]}

assert data["doctor_version"] == 3
assert data["dependency_checks"] is True
assert checks["dependencies.contract"]["status"] == "PASS"
assert checks["dependencies.required"]["status"] == "PASS"
assert checks["dependencies.optional"]["status"] == "WARN"
assert data["dependencies"]["required"]["missing"] == []
assert data["dependencies"]["required"]["satisfied"] == data["dependencies"]["required"]["total"]
assert len(data["dependencies"]["optional"]["missing"]) > 0
PYDEPS

rm -f "$FAKE_BIN/hyprctl"

set +e
PATH="$FAKE_BIN" "$DOCTOR" \
  --home "$HOME_SANDBOX" \
  --no-session \
  --dependencies \
  --json >"$TMP/dependencies-missing-required.json"
DEPENDENCY_CODE=$?
set -e

[[ "$DEPENDENCY_CODE" == "1" ]] \
  || die "doctor should fail when a required dependency is missing, got $DEPENDENCY_CODE"

python3 - "$TMP/dependencies-missing-required.json" <<'PYDEPS'
from pathlib import Path
import json
import sys

data = json.loads(Path(sys.argv[1]).read_text())
checks = {item["id"]: item for item in data["checks"]}

assert data["result"] == "FAIL"
assert checks["dependencies.required"]["status"] == "FAIL"
missing = {item["id"] for item in data["dependencies"]["required"]["missing"]}
assert "hyprland" in missing, missing
PYDEPS

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

pass "doctor clean state, dependency preflight, deep drift, missing-file, JSON, and strict behavior"
