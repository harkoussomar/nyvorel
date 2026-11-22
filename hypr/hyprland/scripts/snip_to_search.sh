#!/usr/bin/env bash
set -eu

region=$(slurp) || exit 0
[[ -n "$region" ]] || exit 0
image=$(mktemp "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/nyvorel-lens-region.XXXXXX.png")
trap 'rm -f -- "$image"' EXIT
grim -t png -g "$region" "$image"
helper="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/nyvorel/scripts/system/google-lens-search"
"$helper" "$image"
