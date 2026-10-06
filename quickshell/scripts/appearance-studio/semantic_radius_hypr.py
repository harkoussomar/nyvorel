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

    # Prefer the existing exact `rounding = N` setting. Do not match
    # rounding_power or any other similarly named option.
    pat = re.compile(r"(?m)^(?P<indent>\s*)rounding\s*=\s*[^#\n]+(?P<comment>\s*(?:#.*)?)$")
    match = pat.search(text)
    if match:
        indent = match.group("indent")
        comment = match.group("comment") or ""
        text = text[:match.start()] + f"{indent}rounding = {value}{comment}" + text[match.end():]
    else:
        begin = "# >>> appearance-studio-window-radius >>>"
        end = "# <<< appearance-studio-window-radius <<<"
        block = f"{begin}\ndecoration {{\n    rounding = {value}\n}}\n{end}\n"
        managed = re.compile(re.escape(begin) + r".*?" + re.escape(end) + r"\n?", re.S)
        if managed.search(text):
            text = managed.sub(block, text, count=1)
        else:
            if text and not text.endswith("\n"):
                text += "\n"
            text += "\n" + block

    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(text)
    tmp.replace(path)


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[1] != "window":
        die("usage: semantic_radius_hypr.py window <0..40>")

    value = clamp(sys.argv[2])
    subprocess.run(
        ["hyprctl", "keyword", "decoration:rounding", str(value)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )

    config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    persist_rounding(config_home / "hypr/custom/general.conf", value)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
