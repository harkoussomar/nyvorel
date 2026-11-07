#!/usr/bin/env python3
"""Compare the native managed palette with the preserved Python generator.

This reads source files and writes no live appearance state or display output.
"""

from pathlib import Path
import json
import os
import tempfile
import subprocess

CRATE = Path(__file__).resolve().parents[1]
ROOT = CRATE.parents[1]
RUST = CRATE / "target/release/nyvorel-appearance-studio"
PYTHON = Path.home() / ".local/state/quickshell/.venv/bin/python"
LEGACY = ROOT / "quickshell/scripts/colors/generate_colors_material.py"
TERMS = ROOT / "quickshell/scripts/colors/terminal/scheme-base.json"
SCHEMES = (
    "scheme-tonal-spot", "scheme-vibrant", "scheme-expressive",
    "scheme-neutral", "scheme-rainbow", "scheme-fruit-salad",
    "scheme-fidelity", "scheme-content", "scheme-monochrome",
)


def palette(command):
    result = subprocess.run(command, text=True, capture_output=True, timeout=20, check=True)
    return dict(line.removeprefix("$").removesuffix(";").split(": ", 1)
                for line in result.stdout.splitlines())


def distance(left, right):
    return max(abs(int(left[index:index + 2], 16) - int(right[index:index + 2], 16))
               for index in (1, 3, 5))


def main():
    if not RUST.is_file() or not PYTHON.is_file():
        raise SystemExit("Build the Rust backend and retain the legacy test venv first")
    cases = 0
    for seed in ("#A06D2C", "#3478B8"):
        for mode in ("dark", "light"):
            for scheme in SCHEMES:
                args = ["--color", seed, "--mode", mode, "--scheme", scheme,
                        "--termscheme", str(TERMS), "--blend_bg_fg", "--harmony", "0.6",
                        "--harmonize_threshold", "100", "--term_fg_boost", "0.35"]
                old = palette([str(PYTHON), str(LEGACY), *args])
                new = palette([str(RUST), "__material-scss", *args])
                assert old.keys() == new.keys(), (seed, mode, scheme, old.keys() ^ new.keys())
                assert old["darkmode"] == new["darkmode"]
                for index in range(16):
                    name = f"term{index}"
                    assert distance(old[name], new[name]) <= 2, (
                        seed, mode, scheme, name, old[name], new[name]
                    )
                cases += 1
    for args in (["--color", "invalid"], ["--color", "#123456", "--termscheme", "/missing"]):
        result = subprocess.run([str(RUST), "__material-scss", *args], capture_output=True)
        assert result.returncode != 0 and not result.stdout
    with tempfile.TemporaryDirectory(prefix="appearance-scss-") as directory:
        base = Path(directory)
        config = base / "config"
        state = base / "state"
        bin_dir = base / "bin"
        active = config / "quickshell/nyvorel"
        (active / "scripts/system").mkdir(parents=True)
        (config / "nyvorel").mkdir(parents=True)
        (state / "quickshell/user/generated").mkdir(parents=True)
        bin_dir.mkdir()
        (active / "scripts/system/nyvorel-appearance-studio").symlink_to(RUST)
        (config / "nyvorel/config.json").write_text(json.dumps({
            "appearance": {"wallpaperTheming": {
                "enableAppsAndShell": True, "enableTerminal": False,
                "terminalGenerationProps": {"forceDarkMode": False, "harmony": 0.6,
                                            "harmonizeThreshold": 100, "termFgBoost": 0.35},
            }}
        }))
        for name, body in {
            "matugen": "#!/bin/sh\nexit 0\n",
            "hyprctl": ("#!/bin/sh\nif [ \"$1\" = cursorpos ]; then "
                        "printf '{\"x\":960,\"y\":540}\\n'; else "
                        "printf '[{\"width\":1920,\"height\":1080,\"focused\":true,"
                        "\"scale\":1,\"x\":0,\"y\":0}]\\n'; fi\n"),
        }.items():
            path = bin_dir / name
            path.write_text(body)
            path.chmod(0o755)
        env = os.environ | {
            "XDG_CONFIG_HOME": str(config), "XDG_STATE_HOME": str(state),
            "XDG_CACHE_HOME": str(base / "cache"),
            "PATH": f"{bin_dir}:{os.environ['PATH']}",
            "NYVOREL_APPEARANCE_STUDIO_MANAGED": "1",
            "NYVOREL_APPEARANCE_STUDIO_SKIP_GSETTINGS": "1",
            "NYVOREL_APPEARANCE_STUDIO_SKIP_TERMINAL": "1",
            "NYVOREL_VIRTUAL_ENV": str(base / "missing-python-venv"),
        }
        result = subprocess.run(
            [str(ROOT / "quickshell/scripts/colors/switchwall.sh"), "--noswitch",
             "--mode", "dark", "--type", "scheme-tonal-spot", "--color", "#A06D2C"],
            env=env, capture_output=True, text=True, timeout=20,
        )
        assert result.returncode == 0, result.stderr
        generated = state / "quickshell/user/generated/material_colors.scss"
        assert generated.is_file() and "$term15: #" in generated.read_text()
    print(f"Managed SCSS parity: {cases} schemes; terminal channels within 2/255")


if __name__ == "__main__":
    main()
