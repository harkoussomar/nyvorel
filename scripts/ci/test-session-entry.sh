#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
HOME_TEST="$TMP/home with spaces"
mkdir -p "$HOME_TEST/.config/hypr" "$TMP/bin"
printf '# fixture\n' >"$HOME_TEST/.config/hypr/hyprland.conf"

cat >"$TMP/bin/start-hyprland" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$NYVOREL_TEST_ARGS"
printf '%s\n' "$XDG_SESSION_TYPE" "$XDG_CURRENT_DESKTOP" "$XDG_SESSION_DESKTOP" >"$NYVOREL_TEST_ARGS.env"
SH
chmod 755 "$TMP/bin/start-hyprland"

env -u XDG_CONFIG_HOME -u HYPRLAND_INSTANCE_SIGNATURE \
  HOME="$HOME_TEST" PATH="$TMP/bin:$PATH" \
  "$ROOT/bin/nyvorel" session --check >"$TMP/check.log"
env -u XDG_CONFIG_HOME -u HYPRLAND_INSTANCE_SIGNATURE \
  HOME="$HOME_TEST" PATH="$TMP/bin:$PATH" NYVOREL_TEST_ARGS="$TMP/args" \
  "$ROOT/bin/nyvorel" session

python3 - "$TMP/args" "$HOME_TEST/.config/hypr/hyprland.conf" <<'PY'
from pathlib import Path
import sys
assert Path(sys.argv[1]).read_text().splitlines() == ["--", "--config", sys.argv[2]]
assert Path(sys.argv[1]+".env").read_text().splitlines() == ["wayland", "Hyprland", "Hyprland"]
PY

if env -u XDG_CONFIG_HOME HOME="$HOME_TEST" PATH="$TMP/bin:$PATH" \
  HYPRLAND_INSTANCE_SIGNATURE=already-active NYVOREL_TEST_ARGS="$TMP/forbidden" \
  "$ROOT/bin/nyvorel" session >"$TMP/refused.log" 2>&1; then
  echo 'Session launcher started inside an active Hyprland session' >&2
  exit 1
fi
[[ ! -e "$TMP/forbidden" ]]

grep -q '^Exec=/usr/bin/nyvorel session$' "$ROOT/packaging/nyvorel.desktop"

# The native entry must run the complete first-login activation workflow. A
# direct Quickshell start skips the remaining user units enabled by activation.
grep -qF 'nyvorel activate --session' "$ROOT/hypr/hyprland.lua"
if grep -qF 'systemctl --user start nyvorel-quickshell.service' \
  "$ROOT/hypr/hyprland.lua"; then
  echo 'ERROR: native entry bypasses the Nyvorel activation workflow' >&2
  exit 1
fi

# The native Lua entry must retain the desktop actions formerly supplied by
# custom/keybinds.conf, and the Super-tap helper must use a package-rewritable
# path (package installs do not populate ~/.local/bin).
python3 - "$ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
lua = (root / "hypr/hyprland.lua").read_text()
required = {
    '"SUPER + P"': "quickshell:projectsToggle",
    '"SUPER+ALT + T"': "quickshell:appearanceStudioToggle",
    '"SUPER + Y"': "quickshell:archRemoteToggle",
    '"SUPER + U"': "quickshell:backupRecoveryToggle",
}
for keys, target in required.items():
    assert any(keys in line and target in line for line in lua.splitlines()), (keys, target)
assert 'hl.bind("SUPER+ALT + P", hl.dsp.window.pin()' in lua
assert 'hl.bind("SUPER + P", hl.dsp.window.pin()' not in lua
assert 'local super_scroll = "~/.local/bin/nyvorel-super-scroll"' in lua
helper = (root / "bin/nyvorel-super-scroll").read_text()
assert 'hyprctl dispatch \'hl.dsp.global("quickshell:searchToggle")\'' in helper
assert 'hyprctl dispatch global quickshell:searchToggle' not in helper
for target, path in (
    ("projectsToggle", "quickshell/modules/nyvorel/projectLauncher/ProjectLauncher.qml"),
    ("appearanceStudioToggle", "quickshell/shell.qml"),
    ("archRemoteToggle", "quickshell/modules/nyvorel/archRemote/ArchRemote.qml"),
    ("backupRecoveryToggle", "quickshell/modules/nyvorel/backupRecovery/BackupRecovery.qml"),
):
    assert f'name: "{target}"' in (root / path).read_text(), target
PY

# Native Lua is preferred when present, while explicit launcher selection wins.
printf 'return true\n' >"$HOME_TEST/.config/hypr/hyprland.lua"
env -u XDG_CONFIG_HOME -u HYPRLAND_INSTANCE_SIGNATURE \
  HOME="$HOME_TEST" PATH="$TMP/bin:$PATH" NYVOREL_TEST_ARGS="$TMP/lua-args" \
  "$ROOT/bin/nyvorel" session
python3 - "$TMP/lua-args" "$HOME_TEST/.config/hypr/hyprland.lua" <<'PY'
from pathlib import Path
import sys
assert Path(sys.argv[1]).read_text().splitlines() == ["--", "--config", sys.argv[2]]
PY
env -u XDG_CONFIG_HOME -u HYPRLAND_INSTANCE_SIGNATURE \
  HOME="$HOME_TEST" PATH="$TMP/bin:$PATH" NYVOREL_TEST_ARGS="$TMP/explicit-args" \
  HYPRLAND_CONFIG="$HOME_TEST/.config/hypr/hyprland.conf" \
  "$ROOT/bin/nyvorel" session
python3 - "$TMP/explicit-args" "$HOME_TEST/.config/hypr/hyprland.conf" <<'PY'
from pathlib import Path
import sys
assert Path(sys.argv[1]).read_text().splitlines() == ["--", "--config", sys.argv[2]]
PY
python3 "$ROOT/quickshell/scripts/hyprland/get_keybinds.py" \
  --path "$ROOT/hypr/hyprland/keybinds.conf" >"$TMP/lua-keybinds.json"
python3 - "$TMP/lua-keybinds.json" <<'PY'
import json
import sys
groups = json.load(open(sys.argv[1], encoding="utf-8"))["children"]
binds = [binding for group in groups for section in group["children"] for binding in section["keybinds"]]
assert len(binds) >= 100
assert any(binding["key"] == "I" and binding["mods"] == ["SUPER"] for binding in binds)
assert any(binding["key"] == "R" and set(binding["mods"]) == {"CTRL", "SUPER"} for binding in binds)
PY
echo 'PASS explicit config session launch, active-session guard and package entry'
