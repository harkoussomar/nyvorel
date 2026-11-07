#!/usr/bin/env python3
"""File-only parity for the normal wallpaper and optional Kvantum color path."""

import os
from pathlib import Path
import subprocess
import tempfile

from PIL import Image

CRATE = Path(__file__).resolve().parents[1]
ROOT = CRATE.parents[1]
RUST = CRATE / "target/release/nyvorel-appearance-studio"
PYTHON = Path.home() / ".local/state/quickshell/.venv/bin/python"
LEGACY = ROOT / "quickshell/scripts/colors/generate_colors_material.py"
SCHEME = ROOT / "quickshell/scripts/colors/scheme_for_image.py"


def run(command, env=None):
    return subprocess.run(command, capture_output=True, text=True, timeout=60, env=env)


def rgb_distance(a, b):
    return max(abs(int(a[i:i + 2], 16) - int(b[i:i + 2], 16)) for i in (1, 3, 5))


def image_fixture(path, kind):
    image = Image.new("RGB", (480, 300))
    pixels = image.load()
    for y in range(300):
        for x in range(480):
            if kind == "solid":
                pixels[x, y] = (84, 119, 153)
            elif kind == "split":
                pixels[x, y] = (220, 60, 60) if x < 240 else (20, 90, 210)
            else:
                pixels[x, y] = (x * 255 // 479, y * 255 // 299, (x + y) % 256)
    image.save(path)


def check_images(base):
    for kind in ("solid", "split", "gradient"):
        image = base / f"{kind}.png"
        image_fixture(image, kind)
        old_scheme = run([str(PYTHON), str(SCHEME), str(image)])
        new_scheme = run([str(RUST), "__scheme-for-image", str(image)])
        assert old_scheme.returncode == new_scheme.returncode == 0
        assert old_scheme.stdout.strip() == new_scheme.stdout.strip(), kind
        old_cache, new_cache = base / f"{kind}-old.txt", base / f"{kind}-new.txt"
        common = ["--path", str(image), "--mode", "dark", "--scheme", "scheme-tonal-spot"]
        old = run([str(PYTHON), str(LEGACY), *common, "--cache", str(old_cache)])
        new = run([str(RUST), "__material-scss", *common, "--cache", str(new_cache)])
        assert old.returncode == new.returncode == 0, (old.stderr, new.stderr)
        assert "$term0" not in new.stdout or "$primary: #" in new.stdout
        assert rgb_distance(old_cache.read_text(), new_cache.read_text()) <= 12, kind
    missing = run([str(RUST), "__material-scss", "--path", str(base / "missing.png")])
    assert missing.returncode != 0 and not missing.stdout
    animated = base / "animated.gif"
    Image.new("RGB", (96, 96), (30, 110, 190)).save(
        animated, save_all=True, append_images=[Image.new("RGB", (96, 96), (210, 90, 50))],
        duration=200, loop=0,
    )
    old_cache, new_cache = base / "gif-old.txt", base / "gif-new.txt"
    old = run([str(PYTHON), str(LEGACY), "--path", str(animated), "--cache", str(old_cache)])
    new = run([str(RUST), "__material-scss", "--path", str(animated), "--cache", str(new_cache)])
    assert old.returncode == new.returncode == 0, (old.stderr, new.stderr)
    assert old_cache.read_text() == new_cache.read_text()
    vector = base / "vector.svg"
    vector.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><rect width="100" height="100" fill="#5588aa"/></svg>')
    converted = run([str(RUST), "__material-scss", "--path", str(vector)])
    assert converted.returncode == 0 and "$primary: #" in converted.stdout, converted.stderr


def prepare_kvantum(base, palette):
    config = base / "config"
    state = base / "state"
    source = config / "Kvantum/Colloid"
    destination = config / "Kvantum/MaterialAdw"
    source.mkdir(parents=True)
    destination.mkdir(parents=True)
    (state / "quickshell/user/generated").mkdir(parents=True)
    (state / "quickshell/user/generated/material_colors.scss").write_text(palette)
    (source / "Colloid.svg").write_text('<svg fill="#3c84f7" stroke="#f04a50" color="#444444"/>')
    (source / "ColloidDark.svg").write_text('<svg fill="#5b9bf8" stroke="#31363b" color="#b74aff"/>')
    (destination / "MaterialAdw.kvconfig").write_text('[General]\nwindow.color=#000000\nbutton.color=#000000\n')
    return {"XDG_CONFIG_HOME": str(config), "XDG_STATE_HOME": str(state)}


def check_kvantum(base):
    palette = run([str(RUST), "__material-scss", "--color", "#547799", "--mode", "dark",
                   "--termscheme", str(ROOT / "quickshell/scripts/colors/terminal/scheme-base.json")])
    assert palette.returncode == 0, palette.stderr
    for mode in ("light", "dark"):
        old_base, new_base = base / f"old-{mode}", base / f"new-{mode}"
        old_env = os.environ | prepare_kvantum(old_base, palette.stdout)
        new_env = os.environ | prepare_kvantum(new_base, palette.stdout)
        old_script = ROOT / f"quickshell/scripts/kvantum/adwsvg{'Dark' if mode == 'dark' else ''}.py"
        old = run(["python3", str(old_script)], old_env)
        new = run([str(RUST), "__kvantum-svg", mode], new_env)
        assert old.returncode == new.returncode == 0, (old.stderr, new.stderr)
        old_svg = (old_base / "config/Kvantum/MaterialAdw/MaterialAdw.svg").read_text()
        new_svg = (new_base / "config/Kvantum/MaterialAdw/MaterialAdw.svg").read_text()
        assert old_svg == new_svg, (mode, old_svg, new_svg)
    old_env = os.environ | prepare_kvantum(base / "config-old", palette.stdout)
    new_env = os.environ | prepare_kvantum(base / "config-new", palette.stdout)
    old = run(["python3", str(ROOT / "quickshell/scripts/kvantum/changeAdwColors.py")], old_env)
    new = run([str(RUST), "__kvantum-config"], new_env)
    assert old.returncode == new.returncode == 0, (old.stderr, new.stderr)
    old_config = (base / "config-old/config/Kvantum/MaterialAdw/MaterialAdw.kvconfig").read_text()
    new_config = (base / "config-new/config/Kvantum/MaterialAdw/MaterialAdw.kvconfig").read_text()
    for key in ("window.color", "button.color", "text.color"):
        old_line = next(line for line in old_config.splitlines() if line.startswith(key + "="))
        new_line = next(line for line in new_config.splitlines() if line.startswith(key + "="))
        assert old_line == new_line, (old_line, new_line)


def check_unmanaged_shell(base):
    import json
    config = base / "config"
    state = base / "state"
    active = config / "quickshell/nyvorel/scripts/system"
    active.mkdir(parents=True)
    (active / "nyvorel-appearance-studio").symlink_to(RUST)
    (config / "nyvorel").mkdir(parents=True)
    (state / "quickshell/user/generated").mkdir(parents=True)
    (state / "quickshell/user/generated/color.txt").write_text("#547799")
    (config / "nyvorel/config.json").write_text(json.dumps({
        "appearance": {"palette": {"type": "scheme-tonal-spot", "accentColor": "#547799"},
                       "wallpaperTheming": {"enableAppsAndShell": True, "enableTerminal": False,
                                            "enableQtApps": False,
                                            "terminalGenerationProps": {"forceDarkMode": False,
                                                                        "harmony": 0.8,
                                                                        "harmonizeThreshold": 100,
                                                                        "termFgBoost": 0.35}}},
        "background": {"wallpaperPath": "", "widgets": {"clock": {"cookie": {"aiStyling": False}}}},
    }))
    bin_dir = base / "bin"
    bin_dir.mkdir()
    (bin_dir / "matugen").write_text("#!/bin/sh\nexit 0\n")
    (bin_dir / "hyprctl").write_text(
        '#!/bin/sh\nif [ "$1" = cursorpos ]; then printf \'{"x":960,"y":540}\\n\'; '
        'else printf \'[{"width":1920,"height":1080,"focused":true,"scale":1,"x":0,"y":0}]\\n\'; fi\n'
    )
    for item in bin_dir.iterdir():
        item.chmod(0o755)
    env = os.environ | {
        "XDG_CONFIG_HOME": str(config), "XDG_STATE_HOME": str(state),
        "XDG_CACHE_HOME": str(base / "cache"),
        "PATH": f"{bin_dir}:{os.environ['PATH']}",
        "NYVOREL_APPEARANCE_STUDIO_SKIP_GSETTINGS": "1",
        "NYVOREL_VIRTUAL_ENV": str(base / "missing-python-venv"),
    }
    result = run([str(ROOT / "quickshell/scripts/colors/switchwall.sh"),
                  "--noswitch", "--mode", "dark"], env)
    assert result.returncode == 0, result.stderr
    generated = state / "quickshell/user/generated/material_colors.scss"
    assert generated.is_file() and "$term15: #" in generated.read_text()


def main():
    assert RUST.is_file() and PYTHON.is_file()
    with tempfile.TemporaryDirectory(prefix="nyvorel-unmanaged-color-") as directory:
        base = Path(directory)
        check_images(base)
        check_kvantum(base)
        check_unmanaged_shell(base / "shell")
    print("Wallpaper scheme, image seed, and optional Kvantum parity passed")


if __name__ == "__main__":
    main()
