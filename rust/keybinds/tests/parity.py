#!/usr/bin/env python3
"""Check legacy parity and the native Lua cheatsheet presentation."""

import json
from pathlib import Path
import shutil
import subprocess
import tempfile

CRATE = Path(__file__).resolve().parents[1]
ROOT = CRATE.parents[1]
RUST = CRATE / "target/release/nyvorel-keybinds"
PYTHON = ROOT / "quickshell/scripts/hyprland/get_keybinds.py"
HYPR = ROOT / "hypr"


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
    # Native Lua uses source annotations to hide implementation bindings and
    # restore useful descriptions, so its output intentionally differs from
    # the old Python parser. Legacy conf and plain Lua still retain parity.
    native = result([str(RUST)], live[0])
    native_bindings = count(native)
    assert 30 <= native_bindings < 150, native_bindings
    assert any(binding["comment"] == "Workspace overview"
               for group in native["children"] for section in group["children"]
               for binding in section["keybinds"])
    assert count(result([str(RUST)], live[1])) == 0
    assert result([str(RUST)], live[2])["children"] == []
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
        synthetic = result([str(RUST)], lua)
        assert count(synthetic) == 3
        synthetic_bindings = synthetic["children"][0]["children"][0]["keybinds"]
        assert synthetic_bindings[0]["comment"] == 'Open "app"'
        assert [binding["key"] for binding in synthetic_bindings] == ["A", "B", "C"]
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
    print(f"Keybind checks passed: legacy parity and native Lua cases; {native_bindings} readable native bindings")


if __name__ == "__main__":
    main()
