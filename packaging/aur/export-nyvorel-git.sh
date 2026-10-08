#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${NYVOREL_AUR_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
AUR="${NYVOREL_AUR_CANDIDATE:-$ROOT/packaging/aur/nyvorel-git}"
OUTPUT=""
while (( $# )); do
  case "$1" in
    --output) (( $# >= 2 )) || { echo 'ERROR: --output requires a path' >&2; exit 2; }; OUTPUT="$2"; shift 2 ;;
    *) printf 'ERROR: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done
[[ -n "$OUTPUT" ]] || { echo 'Usage: export-nyvorel-git.sh --output PATH' >&2; exit 2; }
[[ -d "$ROOT/.git" ]] || { echo 'ERROR: upstream repo missing' >&2; exit 1; }
for f in PKGBUILD .SRCINFO nyvorel.install LICENSE; do
  [[ -f "$AUR/$f" && ! -L "$AUR/$f" ]] || { echo "ERROR: missing or linked $f" >&2; exit 1; }
done
[[ ! -e "$OUTPUT" && ! -L "$OUTPUT" ]] || { echo 'ERROR: destination already exists' >&2; exit 1; }
PARENT="$(realpath -m -- "$(dirname -- "$OUTPUT")")"
REPO_REAL="$(realpath -e -- "$ROOT")"
case "$PARENT/" in
  "$REPO_REAL/"|"$REPO_REAL/"*) echo 'ERROR: export inside the repository is forbidden' >&2; exit 1 ;;
esac
mkdir -p -- "$PARENT"
OUTPUT="$PARENT/$(basename -- "$OUTPUT")"
[[ ! -e "$OUTPUT" ]] || { echo 'ERROR: destination became occupied' >&2; exit 1; }
mkdir -- "$OUTPUT"
for f in PKGBUILD .SRCINFO nyvorel.install LICENSE; do
  install -m644 -- "$AUR/$f" "$OUTPUT/$f"
done
[[ "$(find "$OUTPUT" -maxdepth 1 -type f | wc -l)" -eq 4 ]] || { echo 'ERROR: unexpected export files' >&2; exit 1; }
echo 'AUR candidate exported for HUMAN REVIEW ONLY — not published.'
printf 'output=%s\n' "$OUTPUT"
( cd "$OUTPUT" && sha256sum PKGBUILD .SRCINFO nyvorel.install LICENSE )
