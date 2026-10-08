#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$ROOT"
die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
HOME_TEST="$TMP/isolated-home"
mkdir -p "$HOME_TEST"
./install.sh --target-home "$HOME_TEST" --dry-run --no-activate > "$TMP/preview.txt"
grep -q 'Next: review the plan' "$TMP/preview.txt"
[[ ! -e "$HOME_TEST/.local/state/nyvorel/current-install" ]] || die 'preview mutated HOME'
./install.sh --target-home "$HOME_TEST" --yes --no-activate > "$TMP/install.txt"
grep -q 'Installing managed files:' "$TMP/install.txt"
grep -q 'nyvorel welcome' "$TMP/install.txt"
CLI="$HOME_TEST/.local/bin/nyvorel"
[[ -x "$CLI" ]] || die 'CLI missing'
[[ -x "$HOME_TEST/.local/bin/nyvorel-welcome" ]] || die 'welcome helper not executable'
"$CLI" help | grep -q 'welcome'
"$CLI" welcome --help | grep -q '\-\-no-session'
MANIFEST="$(tr -d '\r\n' < "$HOME_TEST/.local/state/nyvorel/current-install")/manifest.json"
BEFORE="$(sha256sum "$MANIFEST" | cut -d' ' -f1)"
set +e
HOME="$HOME_TEST" "$CLI" welcome --no-session --json > "$TMP/welcome.json"
RESULT=$?
set -e
[[ "$RESULT" == 0 || "$RESULT" == 1 ]] || die "unexpected welcome JSON exit: $RESULT"
python3 - "$TMP/welcome.json" "$HOME_TEST" <<'PY'
import json,sys
from pathlib import Path
out=json.load(open(sys.argv[1]))
assert out['schema']==1 and out['product']=='Nyvorel'
assert out['guide']=='first-run' and out['read_only'] is True
assert out['installed'] is True and out['session_checked'] is False
assert out['target_home']==str(Path(sys.argv[2]).resolve())
assert out['next_steps'] and out['status'] in ('READY','READY_WITH_WARNINGS','NEEDS_ATTENTION')
assert out['summary'] and isinstance(out['issues'],list)
assert out['required']['total'] >= 0
PY
set +e
HOME="$HOME_TEST" "$CLI" welcome --no-session > "$TMP/welcome.txt"
RESULT=$?
set -e
[[ "$RESULT" == 0 || "$RESULT" == 1 ]] || die "unexpected welcome text exit: $RESULT"
grep -q 'FIRST-RUN GUIDE' "$TMP/welcome.txt"
grep -q 'Next steps:' "$TMP/welcome.txt"
grep -q 'No installation, package updates' "$TMP/welcome.txt"
AFTER="$(sha256sum "$MANIFEST" | cut -d' ' -f1)"
[[ "$BEFORE" == "$AFTER" ]] || die 'welcome mutated installation manifest'
[[ -x "$CLI" ]] || die 'welcome altered install'
printf 'PASS first-run preview/progress/JSON/text/read-only isolation\n'
