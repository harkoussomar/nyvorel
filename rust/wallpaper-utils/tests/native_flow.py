#!/usr/bin/env python3
"""File-only compatibility checks for the active wallpaper helper contracts."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
from urllib.parse import quote

from PIL import Image, ImageDraw

CRATE = Path(__file__).resolve().parents[1]
ROOT = CRATE.parents[1]
BIN = CRATE / "target/release/nyvorel-wallpaper-utils"
REGIONS = ROOT / "quickshell/scripts/images/find-regions-venv.sh"
PLACEMENT = ROOT / "quickshell/scripts/images/least-busy-region-venv.sh"
THUMBS = ROOT / "quickshell/scripts/thumbnails/thumbgen-venv.sh"


def run(command, *, env=None, cwd=None):
    return subprocess.run(command, capture_output=True, text=True, timeout=60, env=env, cwd=cwd)


def fixture_regions(path):
    image = Image.new("RGB", (800, 500), (35, 39, 43))
    pen = ImageDraw.Draw(image)
    pen.rounded_rectangle((70, 70, 390, 280), radius=22, fill=(202, 215, 229))
    pen.rectangle((470, 110, 730, 390), fill=(120, 175, 90))
    image.save(path)


def fixture_placement(path):
    image = Image.new("RGB", (400, 300), (80, 130, 180))
    pixels = image.load()
    for y in range(300):
        for x in range(210, 400):
            pixels[x, y] = ((x * 37 + y * 19) % 256,
                            (x * 71 + y * 13) % 256,
                            (x * 17 + y * 97) % 256)
    image.save(path)


def check_regions(path, env, folder):
    args = ["--image", str(path), "--hyprctl", "--min-width", "60", "--min-height", "40"]
    old = run(["python3", str(ROOT / "quickshell/scripts/images/find_regions.py"), *args])
    new = run([str(REGIONS), *args], env=env)
    assert old.returncode == new.returncode == 0, (old.stderr, new.stderr)
    former = json.loads(old.stdout)
    native = json.loads(new.stdout)
    assert len(former) == len(native) == 2, (former, native)
    for a, b in zip(former, native):
        assert all(abs(x - y) <= 4 for x, y in zip(a["at"] + a["size"], b["at"] + b["size"])), (a, b)
        assert a["shape"] == b["shape"]
    single = run([str(REGIONS), *args, "--single", "--debug-output", str(folder / "regions-debug.png")], env=env)
    assert single.returncode == 0 and len(json.loads(single.stdout)) == 1
    assert (folder / "regions-debug.png").is_file()
    failure = run([str(REGIONS), "--image", str(folder / "missing.png")], env=env)
    assert failure.returncode == 0 and json.loads(failure.stdout) == []


def check_placement(path, env, folder):
    args = [str(path), "--screen-width", "400", "--screen-height", "300",
            "--width", "100", "--height", "80",
            "--horizontal-padding", "10", "--vertical-padding", "10"]
    for extra in ([], ["--busiest"]):
        old = run(["python3", str(ROOT / "quickshell/scripts/images/least_busy_region.py"), *args, *extra])
        new = run([str(PLACEMENT), *args, *extra], env=env)
        assert old.returncode == new.returncode == 0, (old.stderr, new.stderr)
        a, b = json.loads(old.stdout), json.loads(new.stdout)
        assert (a["center_x"], a["center_y"]) == (b["center_x"], b["center_y"]), (a, b)
        assert abs(a["variance"] - b["variance"]) < 3, (a, b)
        if not extra:
            assert a["dominant_color"] == b["dominant_color"] == "#5082b4"
    drawn = run([str(PLACEMENT), *args, "--visual-output"], env=env, cwd=folder)
    assert drawn.returncode == 0 and (folder / "output.png").is_file()
    largest = run([str(PLACEMENT), str(path), "--screen-width", "400", "--screen-height", "300",
                   "--largest-region", "--variance-threshold", "10", "--horizontal-padding", "10",
                   "--vertical-padding", "10"], env=env)
    assert largest.returncode == 0, largest.stderr
    assert json.loads(largest.stdout).get("width", 0) > 0


def check_thumbnails(folder, env):
    source = folder / "image with space.png"
    Image.new("RGB", (350, 180), (12, 90, 176)).save(source)
    svg = folder / "icon.svg"
    svg.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="100" height="50"><rect width="100" height="50" fill="red"/></svg>')
    output = run([str(THUMBS), "--size", "normal", "--workers", "2", "--machine_progress", "-d", str(folder)], env=env)
    assert output.returncode == 0, output.stderr
    assert "PROGRESS " in output.stdout and " FILE " in output.stdout
    uri = "file://" + quote(str(source), safe="/-._~:@!$&'()*+,;=")
    key = hashlib.md5(uri.encode()).hexdigest()
    cache = Path(env["XDG_CACHE_HOME"]) / "thumbnails/normal" / f"{key}.png"
    assert cache.is_file(), cache
    with Image.open(cache) as thumb:
        assert max(thumb.size) <= 128
        assert thumb.info["Thumb::URI"] == uri
        assert thumb.info["Thumb::MTime"] == str(int(source.stat().st_mtime))
    before = cache.stat().st_mtime_ns
    again = run([str(THUMBS), "--size", "normal", "--machine_progress", "-d", str(folder)], env=env)
    assert again.returncode == 0 and cache.stat().st_mtime_ns == before
    os.utime(source, (source.stat().st_atime, source.stat().st_mtime + 10))
    refresh = run([str(THUMBS), "--size", "normal", "-d", str(folder)], env=env)
    assert refresh.returncode == 0, refresh.stderr
    with Image.open(cache) as thumb:
        assert thumb.info["Thumb::MTime"] == str(int(source.stat().st_mtime))


def main():
    assert BIN.is_file(), "Build the release binary first"
    with tempfile.TemporaryDirectory(prefix="nyvorel-wallpaper-test-") as directory:
        folder = Path(directory)
        config = folder / "config/quickshell/nyvorel/scripts/system"
        config.mkdir(parents=True)
        (config / "nyvorel-wallpaper-utils").symlink_to(BIN)
        env = os.environ | {
            "XDG_CONFIG_HOME": str(folder / "config"),
            "XDG_CACHE_HOME": str(folder / "cache"),
            "NYVOREL_VIRTUAL_ENV": str(folder / "missing-python"),
        }
        region_image = folder / "regions.png"
        placement_image = folder / "placement.png"
        fixture_regions(region_image)
        fixture_placement(placement_image)
        check_regions(region_image, env, folder)
        check_placement(placement_image, env, folder)
        images = folder / "thumbnail folder with space"
        images.mkdir()
        check_thumbnails(images, env)
    print("Rust wallpaper utilities: regions, placement, thumbnail cache and wrappers passed")


if __name__ == "__main__":
    main()
