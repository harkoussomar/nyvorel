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
    data = item.read_bytes().replace(b"@HOME@", b"%h")
    # Unit syntax must be checked against the package, not the executable bits
    # of an unrelated live installation in the test runner's home directory.
    if item.name.endswith(".service.in") and b"ExecStart=%h/.local/bin/" in data:
        lines = data.splitlines()
        data = b"\n".join(
            b"ExecStart=/usr/bin/true" if line.startswith(b"ExecStart=%h/.local/bin/") else line
            for line in lines
        ) + b"\n"
    (output / item.name.removesuffix(".in")).write_bytes(data)

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
