#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/user/.config/hypr/custom" "$TMP/bin" "$TMP/runtime"
cp "$ROOT/hypr/custom/rules.conf" "$TMP/user/.config/hypr/custom/rules.conf"
cp "$ROOT/hypr/custom/appearance-runtime.conf" \
  "$TMP/user/.config/hypr/custom/appearance-runtime.conf"
printf '#!/bin/sh\nexit 0\n' >"$TMP/bin/hyprctl"
chmod +x "$TMP/bin/hyprctl"

export HOME="$TMP/user"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_RUNTIME_DIR="$TMP/runtime"
export HYPRLAND_INSTANCE_SIGNATURE=''
export PATH="$TMP/bin:$PATH"

rules="$XDG_CONFIG_HOME/hypr/custom/rules.conf"
runtime="$XDG_CONFIG_HOME/hypr/custom/appearance-runtime.conf"
rules_sha="$(sha256sum "$rules" | cut -d' ' -f1)"

"$ROOT/bin/nyvorel-glass-runtime" glass >/dev/null
"$ROOT/bin/nyvorel-fluid-runtime" fluid >/dev/null
python3 "$ROOT/quickshell/scripts/appearance-studio/semantic_radius_hypr.py" \
  window 19
grep -qF '# >>> appearance-studio-glass-runtime-v2 >>>' "$runtime"
grep -qF '# >>> nyvorel-fluid-interface-v1 >>>' "$runtime"
grep -qF 'rounding = 19' "$runtime"
[[ "$(sha256sum "$rules" | cut -d' ' -f1)" == "$rules_sha" ]]

runtime_sha="$(sha256sum "$runtime" | cut -d' ' -f1)"
"$ROOT/bin/nyvorel-glass-runtime" glass >/dev/null
"$ROOT/bin/nyvorel-fluid-runtime" fluid >/dev/null
[[ "$(sha256sum "$runtime" | cut -d' ' -f1)" == "$runtime_sha" ]]

"$ROOT/bin/nyvorel-glass-runtime" default >/dev/null
"$ROOT/bin/nyvorel-fluid-runtime" default >/dev/null
if grep -qF '# >>> appearance-studio-glass-runtime-v2 >>>' "$runtime"; then
  echo 'ERROR: Glass runtime block remained after Default' >&2
  exit 1
fi
if grep -qF '# >>> nyvorel-fluid-interface-v1 >>>' "$runtime"; then
  echo 'ERROR: Fluid runtime block remained after Default' >&2
  exit 1
fi
grep -qF 'rounding = 19' "$runtime"
[[ "$(sha256sum "$rules" | cut -d' ' -f1)" == "$rules_sha" ]]

mkdir -p "$XDG_CONFIG_HOME/nyvorel"
printf '#!/bin/sh\nprintf restored > "$NYVOREL_TEST_MARKER"\n' \
  >"$XDG_CONFIG_HOME/nyvorel/video-wallpaper-restore.sh"
chmod +x "$XDG_CONFIG_HOME/nyvorel/video-wallpaper-restore.sh"
export NYVOREL_TEST_MARKER="$TMP/restore-marker"
"$ROOT/hypr/custom/scripts/__restore_video_wallpaper.sh"
[[ "$(cat "$NYVOREL_TEST_MARKER")" == restored ]]

printf 'PASS  runtime-owned appearance and video state leave managed files untouched\n'
