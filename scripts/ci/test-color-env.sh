#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
WHEELHOUSE="${1:-${NYVOREL_COLOR_WHEELHOUSE:-}}"
[[ -n "$WHEELHOUSE" && -d "$WHEELHOUSE" ]] || {
  echo 'Usage: test-color-env.sh WHEELHOUSE_WITH_materialyoucolor_3.0.4' >&2
  exit 2
}

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
TEST_HOME="$TMP/home"
mkdir -p "$TEST_HOME"

"$ROOT/install.sh" --target-home "$TEST_HOME" --yes --no-activate >"$TMP/install.log"

color_env() {
  env -u XDG_CONFIG_HOME -u XDG_STATE_HOME -u NYVOREL_VIRTUAL_ENV \
    HOME="$TEST_HOME" "$ROOT/bin/nyvorel" color-env "$@"
}

color_env --plan >"$TMP/plan.log"
if color_env --install --wheelhouse "$WHEELHOUSE" >"$TMP/refused.log" 2>&1; then
  echo 'Color environment installed without explicit consent' >&2
  exit 1
fi
[[ ! -e "$TEST_HOME/.local/state/quickshell/.venv" ]]

color_env --install --yes --wheelhouse "$WHEELHOUSE" >"$TMP/install-env.log"
color_env --check >"$TMP/check.log"

ENV_ROOT="$TEST_HOME/.local/state/quickshell/.venv"
printf 'personal marker\n' >"$ENV_ROOT/personal-marker"
mv "$ENV_ROOT/bin/python" "$ENV_ROOT/bin/python.disabled"
if color_env --install --yes --wheelhouse "$WHEELHOUSE" >"$TMP/repair-refused.log" 2>&1; then
  echo 'Broken existing environment replaced without --repair' >&2
  exit 1
fi
color_env --install --repair --yes --wheelhouse "$WHEELHOUSE" >"$TMP/repair.log"
color_env --check >"$TMP/repaired-check.log"

BACKUP="$(find "$TEST_HOME/.local/state/quickshell" -maxdepth 1 -type d -name '.venv.before-*' -print -quit)"
[[ -n "$BACKUP" && "$(cat "$BACKUP/personal-marker")" == 'personal marker' ]]

echo 'PASS disposable source install, explicit color-env consent, generator smoke and repair backup'
