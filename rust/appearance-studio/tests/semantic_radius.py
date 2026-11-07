#!/usr/bin/env python3
"""Compare the one-shot Rust radius writer with the preserved Python writer.

All commands run against disposable XDG directories and a fake hyprctl.
"""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile


CRATE = Path(__file__).resolve().parents[1]
ROOT = CRATE.parents[1]
PYTHON = ROOT / "quickshell/scripts/appearance-studio/semantic_radius_hypr.py"
BINARY = CRATE / "target/release/nyvorel-appearance-studio"
ACTIVE_LUA = Path.home() / ".config/hypr/custom/appearance-runtime.lua"


def run_case(native: bool, original: str | None, value: str) -> None:
    with tempfile.TemporaryDirectory(prefix="semantic-radius-") as temp:
        base = Path(temp)
        fake_bin = base / "bin"
        fake_bin.mkdir()
        fake_hyprctl = fake_bin / "hyprctl"
        fake_hyprctl.write_text("#!/bin/sh\nexit 0\n")
        fake_hyprctl.chmod(0o755)
        outputs = []
        for engine in ("python", "rust"):
            config = base / engine / "config"
            runtime = config / "hypr/custom" / ("appearance-runtime.lua" if native else "appearance-runtime.conf")
            runtime.parent.mkdir(parents=True)
            if native:
                (config / "hypr/hyprland.lua").write_text("-- native config\n")
            if original is not None:
                runtime.write_text(original)
            env = os.environ.copy()
            env.update({
                "XDG_CONFIG_HOME": str(config),
                "XDG_CACHE_HOME": str(base / engine / "cache"),
                "PATH": f"{fake_bin}:{env['PATH']}",
            })
            command = (["python3", str(PYTHON), "window", value]
                       if engine == "python" else [str(BINARY), "__semantic-radius", "window", value])
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=10)
            if result.returncode:
                raise AssertionError(f"{engine} failed: {result.stderr}")
            outputs.append(runtime.read_bytes())
        if outputs[0] != outputs[1]:
            raise AssertionError(f"{native=}, {value=}, original={original!r}: output differs\n"
                                 f"python={outputs[0]!r}\nrust={outputs[1]!r}")


def main() -> None:
    if not BINARY.is_file():
        raise SystemExit("Build the release binary first: cargo build --release --offline")
    lua_cases = [None, "-- other setting\n", "-- other setting\n\n-- >>> Appearance Studio: window radius >>>\nhl.config({[\"decoration\"] = {[\"rounding\"] = 3}})\n-- <<< Appearance Studio: window radius <<<\n"]
    if ACTIVE_LUA.is_file():
        lua_cases.append(ACTIVE_LUA.read_text())
    conf_cases = [None, "decoration {\n    rounding = 8 # note\n}\n", "rounding_power = 2\n",
                  "# >>> appearance-studio-window-radius >>>\ndecoration {\n    rounding = 3\n}\n# <<< appearance-studio-window-radius <<<\n"]
    for value in ("0", "8", "17", "2.5", "41", "-3"):
        for original in lua_cases:
            run_case(True, original, value)
        for original in conf_cases:
            run_case(False, original, value)
    print("Semantic radius parity passed for Lua and conf output, including a copy of the active Lua file")


if __name__ == "__main__":
    main()
