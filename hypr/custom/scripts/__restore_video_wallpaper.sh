#!/usr/bin/env bash
# Managed launcher; the selected wallpaper's restore command is user runtime state.
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
runtime_restore="$config_home/nyvorel/video-wallpaper-restore.sh"
if [[ -x "$runtime_restore" ]]; then
    exec "$runtime_restore"
fi
