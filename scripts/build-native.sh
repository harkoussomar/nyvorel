#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
OUTPUT=""
usage() { printf 'Usage: %s --output DIRECTORY\n' "$0"; }
while (($#)); do
  case "$1" in
    --output) (($# >= 2)) || { usage >&2; exit 2; }; OUTPUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
[[ -n "$OUTPUT" ]] || { usage >&2; exit 2; }
command -v cargo >/dev/null || { echo 'ERROR: Rust cargo is required to build Nyvorel native helpers' >&2; exit 1; }
mkdir -p -- "$OUTPUT"
OUTPUT="$(cd -- "$OUTPUT" && pwd -P)"

build() {
  local source="$1" binary="$2"
  local manifest="$ROOT/$source/Cargo.toml"
  [[ -f "$manifest" && -f "${manifest%/*}/Cargo.lock" ]] || {
    echo "ERROR: native source or lockfile missing: $source" >&2
    exit 1
  }
  cargo build --locked --release --manifest-path "$manifest" --bin "$binary"
  install -m755 "${CARGO_TARGET_DIR:-${manifest%/*}/target}/release/$binary" "$OUTPUT/$binary"
}

build rust/appearance-studio nyvorel-appearance-studio
build rust/arch-remote nyvorel-arch-remote
build rust/backup-recovery nyvorel-backup-recovery
build rust/keybinds nyvorel-keybinds
build rust/operations-center nyvorel-operations
build rust/settings-control nyvorel-settings-control
build rust/wallpaper-utils nyvorel-wallpaper-utils
build rust/network-operations nyvorel-network
