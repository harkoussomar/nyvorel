#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
IMAGE="${NYVOREL_PACKAGE_IMAGE:-archlinux:base}"
RUNTIME="${NYVOREL_CONTAINER_RUNTIME:-}"

die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }

if [[ -z "$RUNTIME" ]]; then
  if command -v podman >/dev/null 2>&1; then
    RUNTIME=podman
  elif command -v docker >/dev/null 2>&1; then
    RUNTIME=docker
  else
    die "neither podman nor docker is available"
  fi
fi

case "$RUNTIME" in
  podman|docker) ;;
  *) die "unsupported container runtime: $RUNTIME" ;;
esac

echo "== Nyvorel Phase 7B pristine Arch package lifecycle =="
echo "runtime=$RUNTIME"
echo "image=$IMAGE"

"$RUNTIME" run --rm \
  -v "$ROOT:/src:ro" \
  "$IMAGE" \
  bash -lc '
set -Eeuo pipefail
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

echo "== Bootstrap package build environment =="
pacman -Syu --noconfirm --needed \
  base-devel git python jq libarchive >/dev/null

useradd -m -U -s /bin/bash builder
useradd -m -U -s /bin/bash nyvoreltest
useradd -m -U -s /bin/bash migratetest

BUILDER_HOME="$(getent passwd builder | cut -d: -f6)"
TEST_HOME="$(getent passwd nyvoreltest | cut -d: -f6)"
MIG_HOME="$(getent passwd migratetest | cut -d: -f6)"
[[ -n "$BUILDER_HOME" && -n "$TEST_HOME" && -n "$MIG_HOME" ]]

install -d -o builder -g builder /work/source
cp -a /src/. /work/source/
chown -R builder:builder /work/source

echo "== Build real package with makepkg =="
runuser -u builder -- env \
  HOME=$BUILDER_HOME \
  NYVOREL_PKG_SOURCE=/work/source \
  bash -lc "cd /work/source && makepkg --nodeps --cleanbuild --force --noconfirm"

PKG="$(find /work/source -maxdepth 1 -type f -name "nyvorel-*.pkg.tar.*" | head -n1)"
[[ -s "$PKG" ]] || { echo "ERROR: package archive missing" >&2; exit 1; }

echo "package=$PKG"

echo "== Audit archive filesystem ownership =="
bsdtar -tf "$PKG" > /work/package-files.txt

grep -q "^usr/bin/nyvorel$" /work/package-files.txt
grep -q "^usr/lib/nyvorel/bin/nyvorel-doctor$" /work/package-files.txt
grep -q "^usr/share/nyvorel/quickshell/shell.qml$" /work/package-files.txt
grep -q "^usr/lib/systemd/user/nyvorel-quickshell.service$" /work/package-files.txt
grep -q "^usr/share/icons/hicolor/scalable/apps/nyvorel.svg$" /work/package-files.txt

if grep -Eq "^(home|root|usr/local)/" /work/package-files.txt; then
  grep -E "^(home|root|usr/local)/" /work/package-files.txt >&2
  echo "ERROR: forbidden package path" >&2
  exit 1
fi

HOME_BEFORE="$(find $TEST_HOME -xdev -printf "%P %y %s %T@\n" | sort | sha256sum | awk "{print \$1}")"

echo "== pacman install must not mutate user HOME =="
pacman -Udd --noconfirm "$PKG" >/dev/null

HOME_AFTER="$(find $TEST_HOME -xdev -printf "%P %y %s %T@\n" | sort | sha256sum | awk "{print \$1}")"
[[ "$HOME_BEFORE" == "$HOME_AFTER" ]] || {
  echo "ERROR: pacman installation mutated $TEST_HOME" >&2
  exit 1
}

[[ -x /usr/bin/nyvorel ]]
[[ -x /usr/lib/nyvorel/bin/nyvorel-package-install ]]
[[ -s /usr/share/nyvorel/package-metadata.json ]]

echo "== Package payload permissions must support arbitrary users =="
BAD_PACKAGE_FILES="$(find /usr/share/nyvorel -type f ! -perm -004 -print)"
BAD_PACKAGE_DIRS="$(find /usr/share/nyvorel -type d ! -perm -005 -print)"
if [[ -n "$BAD_PACKAGE_FILES" || -n "$BAD_PACKAGE_DIRS" ]]; then
  printf "%s\n" "$BAD_PACKAGE_FILES" "$BAD_PACKAGE_DIRS" >&2
  echo "ERROR: package payload is not readable/traversable by arbitrary users" >&2
  exit 1
fi

if grep -RIlF "@HOME@" /usr/lib/systemd/user/nyvorel-* >/dev/null 2>&1; then
  echo "ERROR: package user units contain @HOME@" >&2
  exit 1
fi
if grep -RIlF ".local/bin/nyvorel" \
  /usr/lib/systemd/user/nyvorel-* \
  /usr/share/nyvorel/quickshell \
  /usr/share/nyvorel/hypr \
  /usr/share/nyvorel/integrations \
  >/dev/null 2>&1; then
  grep -RInF ".local/bin/nyvorel" \
    /usr/lib/systemd/user/nyvorel-* \
    /usr/share/nyvorel/quickshell \
    /usr/share/nyvorel/hypr \
    /usr/share/nyvorel/integrations >&2 || true
  echo "ERROR: package payload still references legacy user-local Nyvorel helpers" >&2
  exit 1
fi

grep -qF "Path(\"/usr/lib/nyvorel/bin/nyvorel-glass-runtime\")" \
  /usr/share/nyvorel/quickshell/scripts/appearance-studio/appearance_studio.py
grep -qF "Path(\"/usr/lib/nyvorel/bin/nyvorel-fluid-runtime\")" \
  /usr/share/nyvorel/quickshell/scripts/appearance-studio/appearance_studio.py
grep -qF "/usr/lib/nyvorel/bin/nyvorel-scroll-settings" \
  /usr/share/nyvorel/quickshell/modules/settings/GeneralConfig.qml

echo "== Fresh package user materialization =="
SENTINEL="pre-package-shell"
runuser -u nyvoreltest -- mkdir -p "$TEST_HOME/.config/quickshell/nyvorel"
printf "%s\n" "$SENTINEL" >"$TEST_HOME/.config/quickshell/nyvorel/shell.qml"
chown nyvoreltest:nyvoreltest "$TEST_HOME/.config/quickshell/nyvorel/shell.qml"

runuser -u nyvoreltest -- env HOME=$TEST_HOME \
  /usr/bin/nyvorel install \
  --target-home $TEST_HOME \
  --yes \
  --no-activate >/work/package-install.log

CURRENT=$TEST_HOME/.local/state/nyvorel/current-install
[[ -s "$CURRENT" ]]
STATE="$(tr -d "\r\n" <"$CURRENT")"

python3 - "$STATE/manifest.json" <<PY
from pathlib import Path
import json,sys
d=json.loads(Path(sys.argv[1]).read_text())
assert d["schema"]==1
assert d["product"]=="Nyvorel"
assert d["status"]=="installed"
assert d["source_kind"]=="package"
assert d["source_root"]=="/usr/share/nyvorel"
dest={e["destination"] for e in d["entries"]}
assert ".config/quickshell/nyvorel/shell.qml" in dest
assert ".config/hypr/hyprland.conf" in dest
assert not any(x.startswith(".local/bin/nyvorel") for x in dest)
assert not any(x.startswith(".config/systemd/user/nyvorel-") for x in dest)
assert ".local/share/nyvorel/dependencies/arch.json" not in dest
print("package_manifest_entries="+str(len(d["entries"])))
PY

[[ ! -e $TEST_HOME/.local/bin/nyvorel ]]
[[ ! -e $TEST_HOME/.config/systemd/user/nyvorel-quickshell.service ]]

echo "== Package-aware doctor/bootstrap =="
runuser -u nyvoreltest -- env HOME=$TEST_HOME \
  /usr/bin/nyvorel doctor \
  --home $TEST_HOME \
  --no-session \
  --json >/work/doctor.json

python3 - /work/doctor.json <<PY
from pathlib import Path
import json,sys
d=json.loads(Path(sys.argv[1]).read_text())
assert d["source_kind"]=="package"
checks={x["id"]:x for x in d["checks"]}
assert checks["install.core"]["status"]=="PASS"
assert checks["install.systemd-files"]["status"]=="PASS"
assert checks["manifest.state"]["status"]=="PASS"
assert checks["manifest.contract"]["status"]=="PASS"
assert checks["dependencies.contract"]["status"]=="PASS"
assert checks["package.shadowing"]["status"]=="PASS"
PY

runuser -u nyvoreltest -- env HOME=$TEST_HOME \
  /usr/bin/nyvorel bootstrap --list-optional --json >/work/bootstrap.json

python3 - /work/bootstrap.json <<PY
from pathlib import Path
import json,sys
d=json.loads(Path(sys.argv[1]).read_text())
assert d["mode"]=="optional-catalog"
assert d["mutation_performed"] is False
assert d["optional_count"]==32
PY

echo "== Build/install pkgrel=2; pacman upgrade must not touch HOME =="
cp -a /work/source /work/source-v2
sed -i "s/^pkgrel=1$/pkgrel=2/" /work/source-v2/PKGBUILD
printf "\n// phase7b-package-v2\n" >> /work/source-v2/quickshell/settings.qml
chown -R builder:builder /work/source-v2

runuser -u builder -- env \
  HOME=$BUILDER_HOME \
  NYVOREL_PKG_SOURCE=/work/source-v2 \
  bash -lc "cd /work/source-v2 && makepkg --nodeps --cleanbuild --force --noconfirm"

PKG2="$(find /work/source-v2 -maxdepth 1 -type f -name "nyvorel-*.pkg.tar.*" | head -n1)"
[[ -s "$PKG2" ]]

HOME_BEFORE_UPGRADE="$(find $TEST_HOME -xdev -printf "%P %y %s %T@\n" | sort | sha256sum | awk "{print \$1}")"
pacman -Udd --noconfirm "$PKG2" >/dev/null
HOME_AFTER_UPGRADE="$(find $TEST_HOME -xdev -printf "%P %y %s %T@\n" | sort | sha256sum | awk "{print \$1}")"

[[ "$HOME_BEFORE_UPGRADE" == "$HOME_AFTER_UPGRADE" ]] || {
  echo "ERROR: package upgrade automatically mutated user HOME" >&2
  exit 1
}

grep -q "phase7b-package-v2" /usr/share/nyvorel/quickshell/settings.qml
if grep -q "phase7b-package-v2" $TEST_HOME/.config/quickshell/nyvorel/settings.qml; then
  echo "ERROR: package upgrade silently synchronized HOME" >&2
  exit 1
fi

echo "== Explicit package sync applies pkgrel=2 user payload =="
runuser -u nyvoreltest -- env HOME=$TEST_HOME \
  /usr/bin/nyvorel update \
  --target-home $TEST_HOME \
  --yes \
  --no-activate >/work/package-sync.log

grep -q "phase7b-package-v2" $TEST_HOME/.config/quickshell/nyvorel/settings.qml

echo "== Package removal preserves user config/state/backups =="
HOME_BEFORE_REMOVE="$(find $TEST_HOME -xdev -printf "%P %y %s %T@\n" | sort | sha256sum | awk "{print \$1}")"
pacman -Rdd --noconfirm nyvorel >/dev/null
HOME_AFTER_REMOVE="$(find $TEST_HOME -xdev -printf "%P %y %s %T@\n" | sort | sha256sum | awk "{print \$1}")"

[[ "$HOME_BEFORE_REMOVE" == "$HOME_AFTER_REMOVE" ]] || {
  echo "ERROR: package removal mutated user HOME" >&2
  exit 1
}
[[ -s $TEST_HOME/.local/state/nyvorel/current-install ]]
[[ -s $TEST_HOME/.config/quickshell/nyvorel/shell.qml ]]

echo "== Reinstall package without HOME mutation =="
pacman -Udd --noconfirm "$PKG2" >/dev/null
HOME_AFTER_REINSTALL="$(find $TEST_HOME -xdev -printf "%P %y %s %T@\n" | sort | sha256sum | awk "{print \$1}")"
[[ "$HOME_AFTER_REMOVE" == "$HOME_AFTER_REINSTALL" ]] || {
  echo "ERROR: package reinstall mutated user HOME" >&2
  exit 1
}

echo "== Explicit source-clone -> package migration =="
MIG_SOURCE=/work/source-clone-fixture
rm -rf "$MIG_SOURCE"
mkdir -p "$MIG_SOURCE"

# /work/source is the bind-mounted test repository and may preserve host-only
# modes (for example 0600). A real source clone is owned by the user running
# Nyvorel, so create a detached fixture and transfer ownership to migratetest.
tar -C /work/source   --exclude=.git   --exclude=pkg   --exclude=src   --exclude="*.pkg.tar.*"   -cf - . | tar -C "$MIG_SOURCE" -xf -
chown -R migratetest:migratetest "$MIG_SOURCE"

MIG_UNREADABLE="$(runuser -u migratetest -- find "$MIG_SOURCE" -type f ! -readable -print -quit)"
MIG_UNSEARCHABLE="$(runuser -u migratetest -- find "$MIG_SOURCE" -type d ! -executable -print -quit)"
[[ -z "$MIG_UNREADABLE" ]] || {
  echo "ERROR: source-clone fixture contains unreadable file: $MIG_UNREADABLE" >&2
  exit 1
}
[[ -z "$MIG_UNSEARCHABLE" ]] || {
  echo "ERROR: source-clone fixture contains unsearchable directory: $MIG_UNSEARCHABLE" >&2
  exit 1
}

[[ "$(stat -c %U "$MIG_SOURCE/hypr/hyprland-gui.conf")" == "migratetest" ]]
runuser -u migratetest -- test -r "$MIG_SOURCE/hypr/hyprland-gui.conf"
MIG_SENTINEL="pre-source-clone-shell"
runuser -u migratetest -- mkdir -p "$MIG_HOME/.config/quickshell/nyvorel"
printf "%s\n" "$MIG_SENTINEL" >"$MIG_HOME/.config/quickshell/nyvorel/shell.qml"
chown migratetest:migratetest "$MIG_HOME/.config/quickshell/nyvorel/shell.qml"

runuser -u migratetest -- env HOME=$MIG_HOME \
  "$MIG_SOURCE/install.sh" \
  --target-home $MIG_HOME \
  --yes \
  --no-activate >/work/source-clone-install.log

[[ -x $MIG_HOME/.local/bin/nyvorel ]]

set +e
runuser -u migratetest -- env HOME=$MIG_HOME \
  /usr/bin/nyvorel install \
  --target-home $MIG_HOME \
  --dry-run \
  --no-activate >/work/migrate-refuse.out 2>/work/migrate-refuse.err
MIG_REFUSE=$?
set -e
[[ "$MIG_REFUSE" == 3 ]]
grep -Eq "never migrated implicitly|intentionally explicit" /work/migrate-refuse.err

runuser -u migratetest -- env HOME=$MIG_HOME \
  /usr/bin/nyvorel install \
  --target-home $MIG_HOME \
  --migrate-source-clone \
  --yes \
  --no-activate >/work/migrate.log

MIG_CURRENT=$MIG_HOME/.local/state/nyvorel/current-install
MIG_STATE="$(tr -d "\r\n" <"$MIG_CURRENT")"

python3 - "$MIG_STATE/manifest.json" <<PY
from pathlib import Path
import json,sys
d=json.loads(Path(sys.argv[1]).read_text())
assert d["source_kind"]=="package"
assert d["update"]["from_source_kind"]=="source-clone"
assert d["update"]["to_source_kind"]=="package"
PY

[[ ! -e $MIG_HOME/.local/bin/nyvorel ]]
[[ ! -e $MIG_HOME/.local/share/nyvorel/dependencies/arch.json ]]
[[ ! -e $MIG_HOME/.config/systemd/user/nyvorel-quickshell.service ]]

echo "== User recovery after package lifecycle =="
runuser -u nyvoreltest -- env HOME=$TEST_HOME \
  /usr/bin/nyvorel uninstall \
  --target-home $TEST_HOME \
  --yes \
  --no-deactivate >/work/package-uninstall.log

[[ "$(cat $TEST_HOME/.config/quickshell/nyvorel/shell.qml)" == "$SENTINEL" ]]
[[ ! -e $TEST_HOME/.local/state/nyvorel/current-install ]]

runuser -u migratetest -- env HOME=$MIG_HOME \
  /usr/bin/nyvorel uninstall \
  --target-home $MIG_HOME \
  --yes \
  --no-deactivate >/work/migrate-uninstall.log

[[ "$(cat $MIG_HOME/.config/quickshell/nyvorel/shell.qml)" == "$MIG_SENTINEL" ]]
[[ ! -e $MIG_HOME/.local/state/nyvorel/current-install ]]

echo "PASS  makepkg, pacman install/upgrade/remove/reinstall, package sync, explicit migration and recovery"
'

echo "PASS  pristine Arch package lifecycle"
