#!/usr/bin/env python3
"""Read literal Lua binds without executing config or contacting Hyprland.

Run with the already installed HyprMod interpreter. Emits the legacy
cheatsheet helper's input format, including explicit Lua descriptions.
"""
import sys
from pathlib import Path
from hyprland_config import load_lua, serialize_hyprlang
from hyprland_config._hyprlang._bind import parse_bind_line


def render(path):
    lines = ["#!", "##! Lua keybinds"]
    for line in serialize_hyprlang(load_lua(Path(path))).splitlines():
        bind = parse_bind_line(line)
        if bind is None:
            continue
        if bind.description.startswith("[hidden]"):
            continue
        comment = " # " + bind.description if bind.description else ""
        lines.append("bind = " + ", ".join(("+".join(bind.mods), bind.key, bind.dispatcher, bind.arg)) + comment)
    if len(lines) == 2:
        return ""
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    print(render(sys.argv[1]), end="")
