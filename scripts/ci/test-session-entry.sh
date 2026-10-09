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
PY

if env -u XDG_CONFIG_HOME HOME="$HOME_TEST" PATH="$TMP/bin:$PATH" \
  HYPRLAND_INSTANCE_SIGNATURE=already-active NYVOREL_TEST_ARGS="$TMP/forbidden" \
  "$ROOT/bin/nyvorel" session >"$TMP/refused.log" 2>&1; then
  echo 'Session launcher started inside an active Hyprland session' >&2
  exit 1
fi
[[ ! -e "$TMP/forbidden" ]]

grep -q '^Exec=/usr/bin/nyvorel session$' "$ROOT/packaging/nyvorel.desktop"
echo 'PASS explicit config session launch, active-session guard and package entry'
