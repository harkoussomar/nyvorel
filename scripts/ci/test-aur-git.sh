#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${NYVOREL_AUR_UPSTREAM_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
AUR="${NYVOREL_AUR_CANDIDATE:-$ROOT/packaging/aur/nyvorel-git}"
IMAGE="${NYVOREL_AUR_PACKAGE_IMAGE:-archlinux:base}"
RUNTIME="${NYVOREL_CONTAINER_RUNTIME:-}"

die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }

echo "== Nyvorel Phase 7C AUR Git readiness =="

python3 - "$ROOT" "$AUR" <<'PY'
from pathlib import Path
import json,re,sys
root,aur=(Path(x) for x in sys.argv[1:])
candidate=(aur/"PKGBUILD").read_text()
canonical=(root/"PKGBUILD").read_text()
contract=json.loads((aur.parent.parent/"aur-readiness-contract.json").read_text())
assert contract["phase"]=="7C" and contract["status"]=="aur-git-prepared-not-published"
assert contract["aur_submission_performed"] is False
assert contract["stable_release_performed"] is False
assert contract["package_automatic_home_mutation"] is False
assert (aur/"nyvorel.install").read_bytes()==(root/"nyvorel.install").read_bytes()
assert candidate.count("package() {\n")==1 and canonical.count("package() {\n")==1
body=candidate.split("package() {\n",1)[1]
original=canonical.split("package() {\n",1)[1]
assert body.count('local _src="$srcdir/nyvorel"')==1
assert body.count('"package_name":"nyvorel-git",')==1
body=body.replace('local _src="$srcdir/nyvorel"','local _src="$_nyvorel_source"',1)
body=body.replace('"package_name":"nyvorel-git",','"package_name":"nyvorel",',1)
assert body==original, "AUR package() has drifted from canonical Phase 7B recipe"
assert "makedepends=('git')" not in candidate, 'git already belongs to runtime depends'
for marker in (
  "pkgname=nyvorel-git",
  "provides=(\"nyvorel=${pkgver}\")",
  "conflicts=('nyvorel')",
  "sha256sums=('SKIP')",
  "nyvorel::git+https://github.com/harkoussomar/nyvorel.git#branch=main",
  "pkgver() {",
):
    assert marker in candidate, f"missing AUR invariant {marker}"
assert "replaces=(" not in candidate
assert "aur.archlinux.org" not in candidate
print("canonical_package_body_equivalence=PASS")
print("AUR_git_metadata_security_boundaries=PASS")
PY

bash -n "$AUR/PKGBUILD"
bash -n "$AUR/nyvorel.install"
[[ -s "$AUR/.SRCINFO" ]] || die "AUR .SRCINFO is missing"

if [[ "${1:-}" == "--static-only" ]]; then
  echo "PASS  static AUR Git readiness"
  exit 0
fi

if [[ -z "$RUNTIME" ]]; then
  if command -v podman >/dev/null 2>&1; then RUNTIME=podman
  elif command -v docker >/dev/null 2>&1; then RUNTIME=docker
  else die "neither Podman nor Docker is available"; fi
fi
[[ "$RUNTIME" == podman || "$RUNTIME" == docker ]] || die "unexpected container runtime"

echo "runtime=$RUNTIME"
echo "image=$IMAGE"

# This uses a local Git mirror of the exact reviewed commit instead of
# live origin/main. Only a disposable copy of source= is changed; the
# publication-ready PKGBUILD always uses GitHub HTTPS.
"$RUNTIME" run --rm \
  -v "$ROOT:/src:ro" \
  -v "$AUR:/aur:ro" \
  "$IMAGE" bash -s <<'ARCH'
set -Eeuo pipefail
export LANG=C.UTF-8 LC_ALL=C.UTF-8

echo "== Bootstrap pristine Arch package builder =="
pacman -Syu --noconfirm --needed base-devel git python jq libarchive >/dev/null

mkdir -p /work/aur
cp /aur/PKGBUILD /aur/.SRCINFO /aur/nyvorel.install /work/aur/
useradd -m -U -s /bin/bash builder
useradd -m -U -s /bin/bash aurtest
BUILDER_HOME="$(getent passwd builder | cut -d: -f6)"
TEST_HOME="$(getent passwd aurtest | cut -d: -f6)"

SOURCE_HEAD="$(git -c safe.directory=/src -C /src rev-parse HEAD)"
git -c safe.directory=/src clone --bare /src /work/upstream.git >/dev/null 2>&1
git --git-dir=/work/upstream.git symbolic-ref HEAD refs/heads/main
[[ "$(git --git-dir=/work/upstream.git rev-parse refs/heads/main)" == "$SOURCE_HEAD" ]]

python3 - /work/aur/PKGBUILD <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
old="nyvorel::git+https://github.com/harkoussomar/nyvorel.git#branch=main"
new="nyvorel::git+file:///work/upstream.git#branch=main"
assert s.count(old)==1
p.write_text(s.replace(old,new,1))
PY

chown -R builder:builder /work/upstream.git /work/aur
echo "== Reproduce AUR metadata from the real Arch makepkg =="
runuser -u builder -- env HOME="$BUILDER_HOME" bash -c \
  "cd /work/aur && makepkg --printsrcinfo" >/work/srcinfo.from-makepkg
python3 - /work/aur/.SRCINFO /work/srcinfo.from-makepkg <<'PY'
from pathlib import Path
import sys
a=Path(sys.argv[1]).read_text()
b=Path(sys.argv[2]).read_text()
# The integration test replaces HTTPS with local Git ONLY in its temporary
# PKGBUILD, so that one source entry is expected to differ.
b=b.replace(
    "git+file:///work/upstream.git#branch=main",
    "git+https://github.com/harkoussomar/nyvorel.git#branch=main",
)
assert a==b, "AUR .SRCINFO differs from makepkg --printsrcinfo"
print("aur_srcinfo_synced=PASS")
PY

echo "== Build the real VCS package with makepkg =="
runuser -u builder -- env HOME="$BUILDER_HOME" bash -c \
  "cd /work/aur && makepkg --nodeps --cleanbuild --force --noconfirm"

mapfile -t packages < <(
  find /work/aur -maxdepth 1 -type f -name "nyvorel-git-*.pkg.tar.zst" -print | sort
)
[[ "${#packages[@]}" -eq 1 ]] || {
  printf "ERROR: expected one nyvorel-git archive, found %s\n" "${#packages[@]}" >&2
  exit 1
}
PKG="${packages[0]}"
PKG_NAME="$(pacman -Qp "$PKG")"
[[ "$PKG_NAME" == nyvorel-git\ * ]] || {
  echo "ERROR: invalid archive package identity: $PKG_NAME" >&2; exit 1;
}
printf 'aur_package=%s\n' "$PKG_NAME"

echo "== Audit VCS version, package provenance and ownership =="
python3 - "$PKG" "$SOURCE_HEAD" <<'PY'
from pathlib import Path
import subprocess,sys,re,tarfile
p=Path(sys.argv[1]); commit=sys.argv[2]
name=subprocess.check_output(["pacman","-Qp",str(p)],text=True).strip()
assert re.fullmatch(r"nyvorel-git [0-9]+(?:\.[0-9]+)+\.r[0-9]+\.g[0-9a-f]+-1",name),name
print("vcs_package_version=PASS")
PY

bsdtar -tf "$PKG" >/work/archive.txt
for expected in \
  usr/bin/nyvorel \
  usr/lib/nyvorel/bin/nyvorel-package-install \
  usr/share/nyvorel/quickshell/shell.qml \
  usr/lib/systemd/user/nyvorel-quickshell.service
do
  grep -qxF "$expected" /work/archive.txt
done
if grep -Eq '^(home|root|usr/local)/' /work/archive.txt; then
  echo "ERROR: AUR archive owns prohibited paths" >&2; exit 1
fi

echo "== Install AUR package with zero automatic HOME mutation =="
BEFORE="$(find "$TEST_HOME" -xdev -printf '%P %y %s %T@\n' | sort | sha256sum)"
pacman -Udd --noconfirm "$PKG" >/dev/null
AFTER="$(find "$TEST_HOME" -xdev -printf '%P %y %s %T@\n' | sort | sha256sum)"
[[ "$BEFORE" == "$AFTER" ]] || { echo "ERROR: pacman modified user HOME" >&2; exit 1; }
pacman -Qq nyvorel-git >/dev/null
[[ -x /usr/bin/nyvorel ]]
[[ -x /usr/lib/nyvorel/bin/nyvorel-package-install ]]
[[ -s /usr/share/nyvorel/package-metadata.json ]]

python3 - "$SOURCE_HEAD" <<'PY'
import json,sys
d=json.load(open("/usr/share/nyvorel/package-metadata.json"))
assert d["package_name"]=="nyvorel-git"
assert d["source_kind"]=="package"
assert d["source_commit"]==sys.argv[1], f"commit mismatch {d['source_commit']}"
print("aur_source_provenance=PASS")
PY

echo "== Explicit non-root materialization and doctor/bootstrap =="
runuser -u aurtest -- env HOME="$TEST_HOME" /usr/bin/nyvorel install \
  --target-home "$TEST_HOME" --yes --no-activate >/work/aur-install.log
[[ -s "$TEST_HOME/.local/state/nyvorel/current-install" ]]
runuser -u aurtest -- env HOME="$TEST_HOME" /usr/bin/nyvorel doctor \
  --home "$TEST_HOME" --no-session --json >/work/aur-doctor.json
runuser -u aurtest -- env HOME="$TEST_HOME" /usr/bin/nyvorel bootstrap \
  --list-optional --json >/work/aur-bootstrap.json
python3 - "$TEST_HOME" <<'PY'
import json,sys
from pathlib import Path
home=Path(sys.argv[1])
ptr=(home/".local/state/nyvorel/current-install").read_text().strip()
manifest=json.loads((Path(ptr)/"manifest.json").read_text())
assert manifest["source_kind"]=="package"
assert manifest["source_root"]=="/usr/share/nyvorel"
assert not (home/".local/bin/nyvorel").exists()
doctor=json.load(open("/work/aur-doctor.json"))
checks={x["id"]:x for x in doctor["checks"]}
for ident in ("install.core","manifest.state","dependencies.contract","package.shadowing"):
    assert checks[ident]["status"]=="PASS",(ident,checks[ident])
bootstrap=json.load(open("/work/aur-bootstrap.json"))
assert bootstrap["mode"]=="optional-catalog"
assert bootstrap["mutation_performed"] is False
print("aur_user_materialization_doctor_bootstrap=PASS")
PY

echo "== Remove package without deleting user config/state =="
BEFORE="$(find "$TEST_HOME" -xdev -printf '%P %y %s %T@\n' | sort | sha256sum)"
pacman -Rdd --noconfirm nyvorel-git >/dev/null
AFTER="$(find "$TEST_HOME" -xdev -printf '%P %y %s %T@\n' | sort | sha256sum)"
[[ "$BEFORE" == "$AFTER" ]]
[[ -s "$TEST_HOME/.local/state/nyvorel/current-install" ]]
[[ -s "$TEST_HOME/.config/quickshell/nyvorel/shell.qml" ]]

echo "PASS  AUR -git build, metadata, provenance, installed lifecycle, and ownership"
ARCH

echo "PASS  Phase 7C AUR Git readiness"
