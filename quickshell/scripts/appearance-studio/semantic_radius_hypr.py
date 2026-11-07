#!/usr/bin/env python3
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path


def die(msg: str) -> None:
    print(msg, file=sys.stderr)
    raise SystemExit(1)


def clamp(value: str) -> int:
    try:
        n = int(round(float(value)))
    except ValueError:
        die(f"Invalid radius: {value}")
    return max(0, min(40, n))


def persist_rounding(path: Path, value: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = path.read_text() if path.exists() else ""

    begin = "-- >>> Appearance Studio: window radius >>>"
    end = "-- <<< Appearance Studio: window radius <<<"
    block = f"{begin}\nhl.config({{decoration = {{rounding = {int(value)}}}}})\n{end}\n"
    managed = re.compile(re.escape(begin) + r".*?" + re.escape(end) + r"\n?", re.S)
    if managed.search(text):
        text = managed.sub(block, text, count=1)
    else:
        material_markers = (
            "-- >>> appearance-studio-glass-runtime-v2 >>>",
            "-- >>> nyvorel-fluid-interface-v1 >>>",
        )
        positions = [text.find(marker) for marker in material_markers]
        positions = [position for position in positions if position >= 0]
        if positions:
            position = min(positions)
            text = text[:position].rstrip("\n") + "\n\n" + block + "\n\n" + text[position:]
        else:
            text = text.rstrip("\n") + "\n\n" + block

    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(text)
    tmp.replace(path)


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[1] != "window":
        die("usage: semantic_radius_hypr.py window <0..40>")

    value = clamp(sys.argv[2])
    subprocess.run(
        ["hyprctl", "repl", f"hl.config({{decoration = {{rounding = {int(value)}}}}})"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )

    config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    persist_rounding(config_home / "hypr/custom/appearance-runtime.lua", value)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
