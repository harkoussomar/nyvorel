#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
pass(){ printf 'PASS  %s\n' "$*"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

CANDIDATE="$TMP/candidate"
mkdir -p "$CANDIDATE"

# Copy the working source, including the uncommitted Phase 3 implementation,
# without making the candidate a Git checkout.
cp -a "$ROOT/." "$CANDIDATE/"
rm -rf "$CANDIDATE/.git"
find "$CANDIDATE" -type d -name __pycache__ -prune -exec rm -rf {} +

printf '\n# ci-update-candidate\n' >>"$CANDIDATE/bin/nyvorel-settings"

cat >"$CANDIDATE/bin/nyvorel-ci-update-fixture" <<'EOF'
#!/usr/bin/env bash
echo "Nyvorel update CI fixture"
EOF
chmod +x "$CANDIDATE/bin/nyvorel-ci-update-fixture"

rm -f "$CANDIDATE/bin/nyvorel-tmux-status"

UPDATER="$ROOT/bin/nyvorel-update"

echo "== Baseline carry-forward and retired-file behavior =="

HOME1="$TMP/home-baseline"
mkdir -p "$HOME1/.config/quickshell/nyvorel"
SENTINEL='pre-nyvorel-shell-baseline'
printf '%s\n' "$SENTINEL" >"$HOME1/.config/quickshell/nyvorel/shell.qml"

./install.sh \
  --target-home "$HOME1" \
  --yes \
  --no-activate >"$TMP/home1-install.log"

OLD_STATE1="$(tr -d '\r\n' <"$HOME1/.local/state/nyvorel/current-install")"
OLD_POINTER1="$(cat "$HOME1/.local/state/nyvorel/current-install")"

"$UPDATER" \
  --target-home "$HOME1" \
  --source "$CANDIDATE" \
  --dry-run \
  --no-activate >"$TMP/home1-dry-run.log"

[[ "$(cat "$HOME1/.local/state/nyvorel/current-install")" == "$OLD_POINTER1" ]] \
  || die "update dry-run changed current-install"
[[ ! -e "$HOME1/.local/bin/nyvorel-ci-update-fixture" ]] \
  || die "update dry-run installed new fixture"
[[ -e "$HOME1/.local/bin/nyvorel-tmux-status" ]] \
  || die "update dry-run retired an old file"

"$UPDATER" \
  --target-home "$HOME1" \
  --source "$CANDIDATE" \
  --yes \
  --no-activate >"$TMP/home1-update.log"

NEW_STATE1="$(tr -d '\r\n' <"$HOME1/.local/state/nyvorel/current-install")"

[[ "$NEW_STATE1" != "$OLD_STATE1" ]] || die "update did not advance state"
[[ -x "$HOME1/.local/bin/nyvorel-ci-update-fixture" ]] \
  || die "new update-managed file missing"
[[ ! -e "$HOME1/.local/bin/nyvorel-tmux-status" ]] \
  || die "retired managed file was not removed"
grep -qF '# ci-update-candidate' "$HOME1/.local/bin/nyvorel-settings" \
  || die "candidate payload change not installed"

python3 - "$NEW_STATE1/manifest.json" "$OLD_STATE1" "$SENTINEL" <<'PY'
from pathlib import Path
import json
import sys

manifest = Path(sys.argv[1])
old_state = Path(sys.argv[2])
sentinel = sys.argv[3]

data = json.loads(manifest.read_text())

assert data["schema"] == 1
assert data["product"] == "Nyvorel"
assert data["status"] == "installed"
assert data["update"]["from_state"] == str(old_state)
assert ".local/bin/nyvorel-tmux-status" in data["update"]["retired_destinations"]

entries = {entry["destination"]: entry for entry in data["entries"]}
assert ".local/bin/nyvorel-ci-update-fixture" in entries

shell = entries[".config/quickshell/nyvorel/shell.qml"]
assert shell["preexisting"] is True
backup = manifest.parent / shell["backup"]
assert backup.read_text().strip() == sentinel
PY

./uninstall.sh \
  --target-home "$HOME1" \
  --yes \
  --no-deactivate >"$TMP/home1-uninstall.log"

[[ "$(cat "$HOME1/.config/quickshell/nyvorel/shell.qml")" == "$SENTINEL" ]] \
  || die "uninstall after update did not restore original pre-Nyvorel shell"
[[ ! -e "$HOME1/.local/bin/nyvorel-ci-update-fixture" ]] \
  || die "uninstall after update did not remove update-added file"
[[ ! -e "$HOME1/.local/bin/nyvorel-tmux-status" ]] \
  || die "retired Nyvorel-created file reappeared after uninstall"

echo "== Changed-file refusal and explicit archive =="

HOME2="$TMP/home-drift"
mkdir -p "$HOME2"

./install.sh \
  --target-home "$HOME2" \
  --yes \
  --no-activate >"$TMP/home2-install.log"

OLD_STATE2="$(tr -d '\r\n' <"$HOME2/.local/state/nyvorel/current-install")"

printf '\nuser-local-edit\n' >>"$HOME2/.local/bin/nyvorel-settings"

set +e
"$UPDATER" \
  --target-home "$HOME2" \
  --source "$CANDIDATE" \
  --yes \
  --no-activate >"$TMP/home2-refusal.log" 2>&1
REFUSAL_CODE=$?
set -e

[[ "$REFUSAL_CODE" == "3" ]] || {
  cat "$TMP/home2-refusal.log"
  die "changed-file update refusal expected exit 3, got $REFUSAL_CODE"
}

[[ "$(tr -d '\r\n' <"$HOME2/.local/state/nyvorel/current-install")" == "$OLD_STATE2" ]] \
  || die "refused update changed current-install"
grep -qF 'user-local-edit' "$HOME2/.local/bin/nyvorel-settings" \
  || die "refused update did not preserve user edit"
[[ ! -e "$HOME2/.local/bin/nyvorel-ci-update-fixture" ]] \
  || die "refused update partially installed candidate"

"$UPDATER" \
  --target-home "$HOME2" \
  --source "$CANDIDATE" \
  --yes \
  --force-changed \
  --no-activate >"$TMP/home2-force.log"

NEW_STATE2="$(tr -d '\r\n' <"$HOME2/.local/state/nyvorel/current-install")"

[[ "$NEW_STATE2" != "$OLD_STATE2" ]] || die "forced update did not advance state"

python3 - "$NEW_STATE2/manifest.json" <<'PY'
from pathlib import Path
import json
import sys

manifest = Path(sys.argv[1])
data = json.loads(manifest.read_text())

archived = data["update"]["changed_files_archived"]
assert ".local/bin/nyvorel-settings" in archived

conflict = manifest.parent / "update-conflicts/.local/bin/nyvorel-settings"
assert conflict.is_file()
assert "user-local-edit" in conflict.read_text()
PY

grep -qF '# ci-update-candidate' "$HOME2/.local/bin/nyvorel-settings" \
  || die "forced update did not install candidate payload"

./uninstall.sh \
  --target-home "$HOME2" \
  --yes \
  --no-deactivate >"$TMP/home2-uninstall.log"

[[ ! -e "$HOME2/.local/bin/nyvorel-settings" ]] \
  || die "uninstall did not remove originally Nyvorel-created settings helper"

pass "dry-run, baseline carry-forward, retirement, refusal, archive, update and uninstall"
