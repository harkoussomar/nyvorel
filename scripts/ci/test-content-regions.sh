#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home"
export XDG_CONFIG_HOME="$HOME/.config"
backend="$XDG_CONFIG_HOME/quickshell/nyvorel/scripts/system/nyvorel-wallpaper-utils"
wrapper="$root/quickshell/scripts/images/find-regions-venv.sh"
mkdir -p "$(dirname "$backend")"

[[ "$("$wrapper" --image missing)" == '[]' ]]
cat >"$backend" <<'BACKEND'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$HOME/native-args"
case "$1" in
  find-regions) printf '%s\n' '[{"at":[1,2],"size":[3,4]}]' ;;
  least-busy-region) printf '%s\n' '{"x":1}' ;;
  thumbnails) printf '%s\n' '/tmp/thumb.png' ;;
esac
BACKEND
chmod +x "$backend"
[[ "$("$wrapper" --image fixture)" == '[{"at":[1,2],"size":[3,4]}]' ]]
[[ "$(cat "$HOME/native-args")" == $'find-regions\n--image\nfixture' ]]
[[ "$("$root/quickshell/scripts/images/least-busy-region-venv.sh" --image fixture)" == '{"x":1}' ]]
[[ "$("$root/quickshell/scripts/thumbnails/thumbgen-venv.sh" --image fixture)" == '/tmp/thumb.png' ]]
cat >"$backend" <<'FAIL'
#!/bin/sh
exit 1
FAIL
chmod +x "$backend"
[[ "$("$wrapper" --image fixture)" == '[]' ]]
printf 'PASS  wallpaper wrappers dispatch to native backend and preserve optional region fallback\n'
