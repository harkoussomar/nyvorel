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

# Copy tracked and non-ignored source, including uncommitted implementation,
# without pulling private runtime backups or a Git checkout into the fixture.
git -C "$ROOT" ls-files --cached --others --exclude-standard -z \
  | tar -C "$ROOT" --null -T - -cf - \
  | tar -C "$CANDIDATE" -xf -
find "$CANDIDATE" -type d -name __pycache__ -prune -exec rm -rf {} +

printf '\n# ci-update-candidate\n' >>"$CANDIDATE/bin/nyvorel-settings"
printf '\n# candidate seed must not replace selected appearance\n' \
  >>"$CANDIDATE/hypr/custom/appearance-runtime.conf"

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
RUNTIME1="$HOME1/.config/hypr/custom/appearance-runtime.conf"
printf '\n# user selected Fluid\n' >>"$RUNTIME1"
RUNTIME_SHA1="$(sha256sum "$RUNTIME1" | cut -d' ' -f1)"
for output in hyprland/colors.conf hyprlock/colors.conf; do
  printf '\n# user-selected Matugen palette\n' >>"$HOME1/.config/hypr/$output"
done
COLOR_SHA1="$(sha256sum "$HOME1/.config/hypr/hyprland/colors.conf" | cut -d' ' -f1)"
LOCK_COLOR_SHA1="$(sha256sum "$HOME1/.config/hypr/hyprlock/colors.conf" | cut -d' ' -f1)"
[[ -f "$HOME1/.config/matugen/config.toml" ]] \
  || die "installer omitted source-owned Matugen config"
python3 - "$HOME1" "$ROOT/bin/nyvorel-doctor" <<'PY'
import json
from pathlib import Path
import subprocess
import sys
home, doctor = sys.argv[1:]
result = subprocess.run(
    [doctor, "--home", home, "--deep", "--json", "--no-session"],
    capture_output=True, text=True, check=False,
)
payload = json.loads(result.stdout)
integrity = [check for check in payload["checks"] if check["id"] == "manifest.integrity"]
assert len(integrity) == 1 and integrity[0]["status"] == "PASS", integrity
PY

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
[[ "$(sha256sum "$RUNTIME1" | cut -d' ' -f1)" == "$RUNTIME_SHA1" ]] \
  || die "update replaced selected appearance runtime state"
[[ "$(sha256sum "$HOME1/.config/hypr/hyprland/colors.conf" | cut -d' ' -f1)" == "$COLOR_SHA1" ]]
[[ "$(sha256sum "$HOME1/.config/hypr/hyprlock/colors.conf" | cut -d' ' -f1)" == "$LOCK_COLOR_SHA1" ]]

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
assert entries[".config/hypr/custom/appearance-runtime.conf"]["ownership"] == "runtime"
assert entries[".config/hypr/hyprland/colors.conf"]["ownership"] == "runtime"
assert entries[".config/hypr/hyprlock/colors.conf"]["ownership"] == "runtime"

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
[[ ! -e "$RUNTIME1" ]] || die "uninstall left runtime config active"
grep -qF 'user selected Fluid' \
  "$NEW_STATE1/uninstall-conflicts/"*/.config/hypr/custom/appearance-runtime.conf \
  || die "uninstall did not archive selected appearance state"
grep -qF 'user-selected Matugen palette' \
  "$NEW_STATE1/uninstall-conflicts/"*/.config/hypr/hyprland/colors.conf \
  || die "uninstall did not archive selected Hyprland palette"

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

echo "== Legacy appearance state migration =="

LEGACY="$TMP/legacy-source"
cp -a "$CANDIDATE" "$LEGACY"
rm "$LEGACY/hypr/custom/appearance-runtime.conf"
cat >>"$LEGACY/hypr/custom/general.conf" <<'EOF'
# >>> Appearance Studio: window radius >>>
decoration { rounding = 8 }
# <<< Appearance Studio: window radius <<<
EOF
cat >>"$LEGACY/hypr/custom/rules.conf" <<'EOF'
# >>> appearance-studio-glass-runtime-v2 >>>
layerrule = match:namespace ^quickshell:.*$, blur on
# <<< appearance-studio-glass-runtime-v2 <<<

# >>> nyvorel-fluid-interface-v1 >>>
layerrule = match:namespace ^quickshell:.*$, xray on
# <<< nyvorel-fluid-interface-v1 <<<
EOF
git -C "$LEGACY" init -q
git -C "$LEGACY" -c core.autocrlf=false -c core.safecrlf=false \
  -c user.name='Nyvorel CI' -c user.email='ci@invalid.example' \
  add -A
git -C "$LEGACY" -c user.name='Nyvorel CI' -c user.email='ci@invalid.example' \
  commit -qm 'Synthetic legacy appearance payload'

HOME3="$TMP/home-legacy"
mkdir -p "$HOME3"
"$LEGACY/install.sh" --target-home "$HOME3" --yes --no-activate \
  >"$TMP/home3-install.log"

# Simulate an older manifest that checksum-owned generated compositor palettes.
python3 - "$HOME3/.local/state/nyvorel/current-install" <<'PY'
import json
from pathlib import Path
import sys
state = Path(Path(sys.argv[1]).read_text().strip())
manifest = state / "manifest.json"
data = json.loads(manifest.read_text())
for entry in data["entries"]:
    if entry["destination"] in {".config/hypr/hyprland/colors.conf", ".config/hypr/hyprlock/colors.conf"}:
        entry.pop("ownership", None)
manifest.write_text(json.dumps(data, indent=2) + "\n")
PY
for output in hyprland/colors.conf hyprlock/colors.conf; do
  printf '\n# palette from the old Appearance Studio\n' >>"$HOME3/.config/hypr/$output"
done

python3 - "$HOME3/.config/hypr/custom/rules.conf" <<'PY'
from pathlib import Path
import re
import sys
path = Path(sys.argv[1])
text = path.read_text()
text, count = re.subn(
    r"(?ms)^# >>> appearance-studio-glass-runtime-v2 >>>\n.*?^# <<< appearance-studio-glass-runtime-v2 <<<\n?",
    "", text,
)
assert count == 1
path.write_text(text.rstrip() + "\n")
PY

cp "$HOME3/.config/hypr/custom/rules.conf" "$TMP/home3-rules-runtime-only.conf"
printf 'windowrule = match:class ^(unrelated-user-edit)$, float on\n' \
  >>"$HOME3/.config/hypr/custom/rules.conf"
set +e
"$UPDATER" --target-home "$HOME3" --source "$CANDIDATE" \
  --yes --no-activate >"$TMP/home3-unrelated-refusal.log" 2>&1
UNRELATED_CODE=$?
set -e
[[ "$UNRELATED_CODE" == "3" ]] \
  || die "legacy migration accepted unrelated managed-file edit"
cp "$TMP/home3-rules-runtime-only.conf" "$HOME3/.config/hypr/custom/rules.conf"

"$UPDATER" --target-home "$HOME3" --source "$CANDIDATE" \
  --yes --no-activate >"$TMP/home3-update.log"
RUNTIME3="$HOME3/.config/hypr/custom/appearance-runtime.conf"
grep -qF '# >>> nyvorel-fluid-interface-v1 >>>' "$RUNTIME3" \
  || die "legacy update lost selected Fluid rules"
if grep -qF '# >>> appearance-studio-glass-runtime-v2 >>>' "$RUNTIME3"; then
  die "legacy update re-enabled removed Glass rules"
fi
grep -qF '# >>> Appearance Studio: window radius >>>' "$RUNTIME3" \
  || die "legacy update lost window radius"
if grep -qF '# >>> nyvorel-fluid-interface-v1 >>>' \
  "$HOME3/.config/hypr/custom/rules.conf"; then
  die "legacy runtime rules remained in managed rules.conf"
fi
for output in hyprland/colors.conf hyprlock/colors.conf; do
  grep -qF 'palette from the old Appearance Studio' "$HOME3/.config/hypr/$output" \
    || die "legacy update replaced generated compositor palette: $output"
done

pass "runtime appearance/palette ownership, legacy migration, baseline carry-forward, retirement, refusal, archive, update and uninstall"
