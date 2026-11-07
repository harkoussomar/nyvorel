#!/usr/bin/env bash
set -Eeuo pipefail
binary="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/nyvorel/scripts/system/nyvorel-wallpaper-utils"
if [[ ! -x "$binary" ]]; then
    echo "Nyvorel wallpaper utility is missing: $binary" >&2
    exit 1
fi
exec "$binary" thumbnails "$@"
