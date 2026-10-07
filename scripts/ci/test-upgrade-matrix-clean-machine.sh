#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
IMAGE="${NYVOREL_UPGRADE_MATRIX_IMAGE:-archlinux:base}"
RUNTIME="${NYVOREL_CONTAINER_RUNTIME:-}"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

if [[ -z "$RUNTIME" ]]; then
  if command -v podman >/dev/null 2>&1; then
    RUNTIME="podman"
  elif command -v docker >/dev/null 2>&1; then
    RUNTIME="docker"
  else
    die "neither podman nor docker is available"
  fi
fi

case "$RUNTIME" in
  podman|docker) ;;
  *) die "unsupported container runtime: $RUNTIME" ;;
esac

echo "== Nyvorel pristine Arch upgrade/recovery matrix =="
echo "runtime=$RUNTIME"
echo "image=$IMAGE"

"$RUNTIME" run --rm \
  -v "$ROOT:/src:ro" \
  "$IMAGE" \
  bash -lc '
set -Eeuo pipefail
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

echo "== Bootstrap pristine Arch userspace =="
pacman -Syu --noconfirm --needed \
  bash coreutils findutils grep sed gawk git python shadow util-linux >/dev/null

id nyvoreltest >/dev/null 2>&1 || useradd -m -U -s /bin/bash nyvoreltest

install -d -o nyvoreltest -g nyvoreltest /work
cp -a /src /work/source
chown -R nyvoreltest:nyvoreltest /work/source

cat >/work/run-upgrade-matrix.sh <<'"'"'USERTEST'"'"'
#!/usr/bin/env bash
set -Eeuo pipefail

export HOME=/home/nyvoreltest
export USER=nyvoreltest
export LOGNAME=nyvoreltest
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"

cd /work/source

git config --global user.name "Nyvorel Phase 6D"
git config --global user.email "phase6d@nyvorel.invalid"
git config --global init.defaultBranch main

bash scripts/ci/test-upgrade-matrix.sh
USERTEST

chmod +x /work/run-upgrade-matrix.sh
chown nyvoreltest:nyvoreltest /work/run-upgrade-matrix.sh

runuser -u nyvoreltest -- /work/run-upgrade-matrix.sh
'

echo "PASS  pristine Arch v0.1.0->v0.1.1 upgrade/recovery matrix"
