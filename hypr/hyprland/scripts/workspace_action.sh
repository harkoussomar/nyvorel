#!/usr/bin/env bash
set -Eeuo pipefail

if (( $# != 2 )) || [[ "$1" != workspace && "$1" != movetoworkspacesilent ]]; then
  echo "Usage: $0 {workspace|movetoworkspacesilent} <target>" >&2
  exit 2
fi

dispatcher="$1"
target="$2"
[[ "$target" =~ ^[a-zA-Z0-9:_+-]+$ ]] || {
  echo "Invalid workspace target: $target" >&2
  exit 2
}

# Keep each group of ten workspaces together when using the number row.
if [[ "$target" =~ ^[0-9]+$ ]]; then
  current="$(hyprctl activeworkspace -j | jq -er '.id | numbers')"
  (( current >= 1 )) || current=1
  target=$(( ((current - 1) / 10) * 10 + target ))
fi

# A Lua Hyprland session expects a Lua dispatcher expression. The old
# `hyprctl dispatch workspace 2` syntax fails to parse under that mode.
if [[ "$dispatcher" == workspace ]]; then
  hyprctl dispatch "hl.dsp.focus({workspace = \"$target\"})"
else
  hyprctl dispatch "hl.dsp.window.move({workspace = \"$target\", follow = false})"
fi
