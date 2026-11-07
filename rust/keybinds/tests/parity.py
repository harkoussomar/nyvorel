#!/usr/bin/env python3
"""Compare native keybind JSON with the preserved Python parser, file only."""

import json
from pathlib import Path
import shutil
import subprocess
import tempfile

CRATE = Path(__file__).resolve().parents[1]
ROOT = CRATE.parents[1]
RUST = CRATE / "target/release/nyvorel-keybinds"
PYTHON = ROOT / "quickshell/scripts/hyprland/get_keybinds.py"
HYPR = Path.home() / ".config/hypr"


def result(program, path):
    output = subprocess.run(program + ["--path", str(path)], capture_output=True, text=True, timeout=15)
    assert output.returncode == 0, (path, output.stderr)
    return json.loads(output.stdout)


def compare(path):
    old = result(["python3", str(PYTHON)], path)
    new = result([str(RUST)], path)
    assert old == new, f"Keybind mismatch: {path}"
    return old


def count(section):
    return len(section["keybinds"]) + sum(count(child) for child in section["children"])


def main():
    assert RUST.is_file()
    live = [HYPR / "hyprland/keybinds.conf", HYPR / "custom/keybinds.conf", HYPR / "hyprland-gui.lua"]
    assert all(path.is_file() for path in live)
    for path in live:
        compare(path)
    with tempfile.TemporaryDirectory(prefix="nyvorel-keybind-parity-") as directory:
        base = Path(directory) / "hypr"
        for branch in ("hyprland", "custom"):
            path = base / branch / "keybinds.conf"
            path.parent.mkdir(parents=True)
            shutil.copyfile(HYPR / branch / "keybinds.conf", path)
            compare(path)
        lua = base / "synthetic.lua"
        lua.write_text(
            'hl.bind("SUPER + A", hl.dsp.exec_cmd("echo hi"), {["description"] = "Open \\"app\\""})\n'
            'hl.bind_release("CTRL + B", hl.dsp.move_focus("l"), {})\n'
            'hl.bind_repeat("ALT + C", hl.dsp.toggle_floating(), {})\n'
        )
        compare(lua)
        fallback = base / "hyprland" / "small.conf"
        fallback.write_text(
            '#! Main\n'
            'bind = SUPER, Return, exec, terminal\n'
            '##! Nested\n'
            'bind = SUPER SHIFT, Q, killactive, # Close app\n'
            'bind = SUPER, H, exec, hidden # [hidden] private\n'
            '#! More\n'
            '#/# bind = SUPER, M, movewindow, l\n'
        )
        compare(fallback)
    print(f"Keybind parity passed: three live files, legacy configs and synthetic cases; {count(result([str(RUST)], live[0]))} live bindings")


if __name__ == "__main__":
    main()
