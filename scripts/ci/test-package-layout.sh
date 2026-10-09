#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$ROOT"

die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }

for path in \
  PKGBUILD \
  .SRCINFO \
  nyvorel.install \
  packaging/package-layout.json \
  packaging/nyvorel-package-install \
  packaging/nyvorel.desktop
do
  [[ -s "$path" ]] || die "missing package implementation file: $path"
done

bash -n PKGBUILD
bash -n nyvorel.install
bash -n packaging/nyvorel-package-install
python3 -m json.tool packaging/package-layout.json >/dev/null

# Bash syntax does not validate Python embedded in PKGBUILD heredocs.
# Compile every package-time Python heredoc before entering makepkg/container CI.
python3 - PKGBUILD <<'PY'
from pathlib import Path
import re
import sys

text=Path(sys.argv[1]).read_text()
for marker in ("PYPAYLOAD", "PYUNITS", "PYMETA"):
    match=re.search(
        rf"<<'{marker}'\n(.*?)\n{marker}(?:\n|$)",
        text,
        flags=re.S,
    )
    if not match:
        raise SystemExit(f"missing PKGBUILD Python heredoc: {marker}")
    compile(match.group(1), f"PKGBUILD:{marker}", "exec")
    print(f"embedded_python_{marker}=PASS")
PY

python3 - packaging/package-layout.json <<'PY'
from pathlib import Path
import json,sys

data=json.loads(Path(sys.argv[1]).read_text())
assert data["schema"]==1
assert data["phase"]=="7B"
assert data["package_name"]=="nyvorel"
assert data["public_cli"]=="/usr/bin/nyvorel"
assert data["helper_root"]=="/usr/lib/nyvorel/bin"
assert data["payload_root"]=="/usr/share/nyvorel"
assert data["systemd_user_root"]=="/usr/lib/systemd/user"
assert data["package_units_use_HOME_token"] is False
assert data["package_units_use_user_local_nyvorel_helpers"] is False
assert data["package_upgrade_mutates_HOME"] is False
assert data["package_remove_deletes_user_state"] is False
assert data["remote_updater_mutates_package_payload"] is False
assert data["source_clone_to_package_migration"]=="explicit-only"
assert data["aur_publication"]=="not-in-7B"
PY

grep -q "^pkgname=nyvorel$" PKGBUILD
grep -q "^pkgver=0.1.0.dev$" PKGBUILD
grep -q "^install=nyvorel.install$" PKGBUILD
grep -qF '/usr/bin/nyvorel' PKGBUILD
grep -qF '/usr/lib/nyvorel' PKGBUILD
grep -qF '/usr/share/nyvorel' PKGBUILD
grep -qF '/usr/lib/systemd/user' PKGBUILD
grep -qF '/usr/share/wayland-sessions/nyvorel.desktop' PKGBUILD

if grep -Eq '^[[:space:]]*(cp|mv|rm|install|mkdir|systemctl)[[:space:]]' nyvorel.install; then
  cat nyvorel.install >&2
  die "nyvorel.install contains mutating command"
fi

if grep -Eq '/home/|\\$HOME|~/' nyvorel.install; then
  grep -En '/home/|\\$HOME|~/' nyvorel.install >&2 || true
  die "package install hook contains user-HOME ownership"
fi

if command -v makepkg >/dev/null 2>&1; then
  TMP="$(mktemp)"
  trap 'rm -f "$TMP"' EXIT
  makepkg --printsrcinfo >"$TMP"
  diff -u .SRCINFO "$TMP" || die ".SRCINFO is not synchronized with PKGBUILD"
fi

echo "PASS  PKGBUILD/.SRCINFO/layout/hook ownership contract"
