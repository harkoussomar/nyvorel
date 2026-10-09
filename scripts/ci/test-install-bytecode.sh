#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/source" "$TMP/home"
for entry in quickshell hypr matugen integrations bin dependencies systemd assets VERSION; do
  cp -a "$ROOT/$entry" "$TMP/source/$entry"
done
mkdir -p "$TMP/source/bin/__pycache__" "$TMP/source/quickshell/scripts/__pycache__"
printf '@HOME@ stale bytecode\n' > "$TMP/source/bin/__pycache__/fixture.pyc"
printf '@HOME@ stale bytecode\n' > "$TMP/source/quickshell/scripts/__pycache__/fixture.pyc"
NYVOREL_SOURCE_ROOT="$TMP/source" "$ROOT/install.sh" \
  --target-home "$TMP/home" --yes --no-activate > "$TMP/install.log"
python3 - "$TMP/home" <<'PY'
from pathlib import Path
import json
import sys
home = Path(sys.argv[1])
state = Path((home / '.local/state/nyvorel/current-install').read_text().strip())
data = json.loads((state / 'manifest.json').read_text())
assert data['status'] == 'installed'
for item in data['entries']:
    path = Path(item['destination'])
    assert '__pycache__' not in path.parts and path.suffix not in {'.pyc', '.pyo'}, path
    assert '.before-' not in path.name and '.pre-' not in path.name, path
assert not list((home / '.config').rglob('*.pyc'))
PY
[[ -f "$TMP/source/bin/__pycache__/fixture.pyc" ]]
printf 'PASS interpreter caches excluded without modifying the source checkout\n'
