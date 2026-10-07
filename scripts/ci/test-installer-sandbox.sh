#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
pass(){ printf 'PASS  %s\n' "$*"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

HOME_SANDBOX="$TMP/home"
mkdir -p "$HOME_SANDBOX/.config/quickshell/nyvorel"

SENTINEL='pre-existing-shell-ci-sentinel'
printf '%s\n' "$SENTINEL" >"$HOME_SANDBOX/.config/quickshell/nyvorel/shell.qml"

echo "== Installer dry-run =="
./install.sh \
  --target-home "$HOME_SANDBOX" \
  --dry-run \
  --no-activate >"$TMP/install-dry-run.log"

[[ "$(cat "$HOME_SANDBOX/.config/quickshell/nyvorel/shell.qml")" == "$SENTINEL" ]] \
  || die "dry-run changed pre-existing file"

[[ ! -e "$HOME_SANDBOX/.local/state/nyvorel/current-install" ]] \
  || die "dry-run created current-install pointer"

echo "== Sandbox install =="
./install.sh \
  --target-home "$HOME_SANDBOX" \
  --yes \
  --no-activate >"$TMP/install.log"

CURRENT="$HOME_SANDBOX/.local/state/nyvorel/current-install"
[[ -s "$CURRENT" ]] || die "current-install pointer missing"

STATE="$(tr -d '\r\n' <"$CURRENT")"
MANIFEST="$STATE/manifest.json"
[[ -s "$MANIFEST" ]] || die "manifest missing"

python3 - "$MANIFEST" "$HOME_SANDBOX" "$(git rev-parse HEAD)" <<'PY'
from pathlib import Path
import json
import sys

manifest = Path(sys.argv[1])
home = Path(sys.argv[2]).resolve()
expected_commit = sys.argv[3]

data = json.loads(manifest.read_text())

assert data["schema"] == 1
assert data["product"] == "Nyvorel"
assert data["status"] == "installed"
assert Path(data["target_home"]).resolve() == home
assert len(data["entries"]) > 500
assert data["source_commit"] == expected_commit

for entry in data["entries"]:
    rel = Path(entry["destination"])
    assert not rel.is_absolute()
    assert ".." not in rel.parts
    assert isinstance(entry.get("installed"), dict)

print(f"manifest_entries={len(data['entries'])}")
PY

BACKUP="$STATE/backup/.config/quickshell/nyvorel/shell.qml"
[[ -f "$BACKUP" ]] || die "pre-existing shell backup missing"
[[ "$(cat "$BACKUP")" == "$SENTINEL" ]] || die "backup content mismatch"

[[ -x "$HOME_SANDBOX/.local/bin/nyvorel-settings" ]] \
  || die "installed helper missing/not executable"

if grep -RIlF '@HOME@' \
  "$HOME_SANDBOX/.config/quickshell/nyvorel" \
  "$HOME_SANDBOX/.config/hypr" \
  "$HOME_SANDBOX/.config/systemd/user" \
  "$HOME_SANDBOX/.local/bin" \
  "$HOME_SANDBOX/.config/fish" \
  "$HOME_SANDBOX/.config/kitty" \
  >"$TMP/unresolved.txt" 2>/dev/null; then
  cat "$TMP/unresolved.txt"
  die "unresolved @HOME@ token exists after sandbox installation"
fi

if find "$HOME_SANDBOX/.config/systemd/user" -type f -name '*.in' -print -quit | grep -q .; then
  find "$HOME_SANDBOX/.config/systemd/user" -type f -name '*.in' -print
  die "systemd .in template survived materialization"
fi

echo "== Recovery dry-run =="
./uninstall.sh \
  --target-home "$HOME_SANDBOX" \
  --dry-run \
  --no-deactivate >"$TMP/uninstall-dry-run.log"

grep -q 'DRY RUN — no files or services changed.' "$TMP/uninstall-dry-run.log" \
  || die "uninstall dry-run marker missing"

echo "== Changed-file refusal =="
printf '\nci-post-install-edit\n' >>"$HOME_SANDBOX/.local/bin/nyvorel-settings"

set +e
./uninstall.sh \
  --target-home "$HOME_SANDBOX" \
  --yes \
  --no-deactivate >"$TMP/uninstall-refusal.log" 2>&1
REFUSAL_CODE=$?
set -e

[[ "$REFUSAL_CODE" == "3" ]] || {
  cat "$TMP/uninstall-refusal.log"
  die "changed-file refusal expected exit 3, got $REFUSAL_CODE"
}

grep -q 'refusing to overwrite/remove changed installed files' "$TMP/uninstall-refusal.log" \
  || die "changed-file refusal reason missing"

echo "== Forced recovery with archive =="
./uninstall.sh \
  --target-home "$HOME_SANDBOX" \
  --yes \
  --no-deactivate \
  --force-changed >"$TMP/uninstall-force.log"

[[ "$(cat "$HOME_SANDBOX/.config/quickshell/nyvorel/shell.qml")" == "$SENTINEL" ]] \
  || die "pre-existing shell file was not restored exactly"

[[ ! -e "$HOME_SANDBOX/.local/bin/nyvorel-settings" ]] \
  || die "Nyvorel-created helper was not removed"

[[ ! -e "$CURRENT" ]] || die "current-install pointer was not removed"
[[ -d "$HOME_SANDBOX/.config/nyvorel" ]] \
  || die "runtime/user config boundary was not retained"

python3 - "$MANIFEST" <<'PY'
from pathlib import Path
import json
import sys

data = json.loads(Path(sys.argv[1]).read_text())
assert data["status"] == "uninstalled"

archived = data.get("uninstall_conflicts_archived") or []
assert ".local/bin/nyvorel-settings" in archived

root = data.get("uninstall_conflict_root")
assert root
assert Path(root, ".local/bin/nyvorel-settings").is_file()

print(f"archived_conflicts={len(archived)}")
PY

pass "sandbox install, manifest, materialization, edit protection, archive, and recovery"
