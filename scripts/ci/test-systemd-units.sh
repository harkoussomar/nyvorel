#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
command -v systemd-analyze >/dev/null || {
  echo 'systemd-analyze is required to validate user units' >&2
  exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

python3 - "$ROOT/systemd" "$TMP" <<'PY'
from pathlib import Path
import sys

source, output = map(Path, sys.argv[1:])
for item in source.glob("*.in"):
    (output / item.name.removesuffix(".in")).write_bytes(
        item.read_bytes().replace(b"@HOME@", b"%h")
    )

for name in ("btop", "fuzzel", "kde-app", "zen-code"):
    stem = f"nyvorel-{name}-style-sync"
    path = (output / f"{stem}.path").read_text()
    timer = (output / f"{stem}.timer").read_text()
    assert f"Unit={stem}.timer" in path
    assert f"Unit={stem}.service" in timer
    assert "OnActiveSec=1s" in timer
    assert "RemainAfterElapse=no" in timer
PY

systemd-analyze verify --user "$TMP"/*
echo 'PASS user-unit syntax and four path-to-timer coalescing chains'
