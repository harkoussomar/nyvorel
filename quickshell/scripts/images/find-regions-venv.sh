#!/usr/bin/env bash
set -Eeuo pipefail

binary="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/nyvorel/scripts/system/nyvorel-wallpaper-utils"
# Region hints are optional; manual selection remains usable on failure.
if [[ ! -x "$binary" ]]; then
    printf '[]\n'
    exit 0
fi
if output="$("$binary" find-regions "$@")"; then
    printf '%s\n' "$output"
else
    printf '[]\n'
fi
