#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$ROOT"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

TARGET="$TMP/target"
mkdir -p "$TARGET"

echo "== Install Phase 5 candidate into isolated HOME =="
./install.sh \
  --target-home "$TARGET" \
  --yes \
  --no-activate >"$TMP/install.log"

CLI="$TARGET/.local/bin/nyvorel"
[[ -x "$CLI" ]] || die "installed Nyvorel CLI missing"
[[ -x "$TARGET/.local/bin/nyvorel-bootstrap" ]] \
  || die "installed bootstrap planner missing"

echo "== Public CLI discoverability =="
"$CLI" help | grep -q 'bootstrap'
[[ "$("$CLI" bootstrap --version)" == "nyvorel bootstrap 2" ]] \
  || die "bootstrap version contract mismatch"

echo "== Optional catalog requires no Arch/pacman probe =="
cat >"$TMP/nonarch-os-release" <<'OS'
ID=not-arch
OS

PACMAN_LOG="$TMP/pacman.log"
: >"$PACMAN_LOG"

cat >"$TMP/fail-pacman" <<'PACMAN'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${NYVOREL_TEST_PACMAN_LOG:?}"
exit 99
PACMAN
chmod +x "$TMP/fail-pacman"

HOME="$TARGET" \
NYVOREL_BOOTSTRAP_OS_RELEASE="$TMP/nonarch-os-release" \
NYVOREL_PACMAN_BIN="$TMP/fail-pacman" \
NYVOREL_TEST_PACMAN_LOG="$PACMAN_LOG" \
  "$CLI" bootstrap --list-optional --json >"$TMP/catalog.json"

python3 - "$TMP/catalog.json" "$TARGET/.local/share/nyvorel/dependencies/arch.json" <<'PY'
from pathlib import Path
import json
import sys

data = json.loads(Path(sys.argv[1]).read_text())
contract = json.loads(Path(sys.argv[2]).read_text())

assert data["schema"] == 1
assert data["product"] == "Nyvorel"
assert data["bootstrap_version"] == 2
assert data["mode"] == "optional-catalog"
assert data["mutation_performed"] is False
assert data["optional_count"] == len(contract["optional"])
assert len(data["optional"]) == len(contract["optional"])

ids = [item["id"] for item in data["optional"]]
assert len(ids) == len(set(ids))
assert set(ids) == {item["id"] for item in contract["optional"]}
assert {"screenshots", "ocr", "clipboard-history", "screen-recording"} <= set(ids)

for item in data["optional"]:
    assert item["command_mode"] in {"any", "all"}
    assert item["package_mode"] in {"any", "all"}
    assert item["commands"]
    assert item["package_hints"]
    assert item["feature"]
PY

[[ ! -s "$PACMAN_LOG" ]] \
  || die "--list-optional unexpectedly invoked the pacman probe"

HOME="$TARGET" \
NYVOREL_BOOTSTRAP_OS_RELEASE="$TMP/nonarch-os-release" \
NYVOREL_PACMAN_BIN="$TMP/fail-pacman" \
NYVOREL_TEST_PACMAN_LOG="$PACMAN_LOG" \
  "$CLI" bootstrap --list-optional >"$TMP/catalog.txt"

grep -q '^screenshots$' "$TMP/catalog.txt"
grep -q '^ocr$' "$TMP/catalog.txt"
grep -q 'no repository probe or package mutation' "$TMP/catalog.txt"
[[ ! -s "$PACMAN_LOG" ]] \
  || die "human optional catalog unexpectedly invoked pacman"

echo "== Invalid optional ID is actionable and non-mutating =="
cat >"$TMP/arch-os-release" <<'OS'
ID=arch
OS

set +e
HOME="$TARGET" \
NYVOREL_BOOTSTRAP_OS_RELEASE="$TMP/arch-os-release" \
NYVOREL_PACMAN_BIN="$TMP/fail-pacman" \
NYVOREL_TEST_PACMAN_LOG="$PACMAN_LOG" \
  "$CLI" bootstrap --optional not-a-real-feature \
  >"$TMP/unknown.out" 2>"$TMP/unknown.err"
UNKNOWN_RC=$?
set -e

[[ "$UNKNOWN_RC" == "2" ]] \
  || die "unknown optional ID should return exit 2"
grep -q 'Available IDs:' "$TMP/unknown.err"
grep -q 'screenshots' "$TMP/unknown.err"
[[ ! -s "$PACMAN_LOG" ]] \
  || die "unknown optional ID unexpectedly invoked pacman"

echo "== Catalog/selection conflict fails before platform/probe =="
set +e
HOME="$TARGET" \
NYVOREL_BOOTSTRAP_OS_RELEASE="$TMP/nonarch-os-release" \
NYVOREL_PACMAN_BIN="$TMP/fail-pacman" \
NYVOREL_TEST_PACMAN_LOG="$PACMAN_LOG" \
  "$CLI" bootstrap --list-optional --optional screenshots \
  >"$TMP/conflict.out" 2>"$TMP/conflict.err"
CONFLICT_RC=$?
set -e

[[ "$CONFLICT_RC" == "2" ]] \
  || die "catalog/selection conflict should return exit 2"
grep -q -- '--list-optional cannot be combined with --optional' "$TMP/conflict.err"
[[ ! -s "$PACMAN_LOG" ]] \
  || die "catalog/selection conflict unexpectedly invoked pacman"

echo "== Doctor/bootstrap installed-contract compatibility =="
"$CLI" doctor \
  --home "$TARGET" \
  --no-session \
  --json >"$TMP/doctor.json"

python3 - "$TMP/doctor.json" <<'PY'
from pathlib import Path
import json
import sys

data = json.loads(Path(sys.argv[1]).read_text())
checks = {item["id"]: item for item in data["checks"]}

assert data["doctor_version"] == 3
assert checks["install.core"]["status"] == "PASS"
assert checks["dependencies.contract"]["status"] == "PASS"
assert data["dependencies"]["contract"]["schema"] == 2
PY

echo "== Documentation discoverability =="
grep -q 'bootstrap --list-optional' README.md
grep -q 'bootstrap --list-optional' INSTALL.md
grep -q 'bootstrap --list-optional' DEPENDENCIES.md

echo "PASS  Phase 5 dependency/bootstrap UX and compatibility contract"
