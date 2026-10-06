#!/usr/bin/env python3
# Appearance Studio wallpaper semantic profiler.
# Produces environment colors, representative colors, accent candidates,
# luminance statistics and wallpaper colorfulness without third-party Python libs.

from __future__ import annotations

import json
import math
import re
import shutil
import subprocess
import sys
from pathlib import Path


def clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    return max(low, min(high, value))


def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def linear_to_srgb(c: float) -> float:
    c = max(0.0, min(1.0, c))
    return 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055


def rgb01(value: str) -> tuple[float, float, float]:
    h = value.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def rgb_hex(rgb: tuple[float, float, float]) -> str:
    return "#" + "".join(f"{round(clamp(c) * 255):02x}" for c in rgb)


def oklab_from_rgb(rgb: tuple[float, float, float]) -> tuple[float, float, float]:
    r, g, b = (srgb_to_linear(c) for c in rgb)

    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b

    l_ = math.copysign(abs(l) ** (1 / 3), l)
    m_ = math.copysign(abs(m) ** (1 / 3), m)
    s_ = math.copysign(abs(s) ** (1 / 3), s)

    return (
        0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
        1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
        0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
    )


def oklab(value: str) -> tuple[float, float, float]:
    return oklab_from_rgb(rgb01(value))


def distance(a: str, b: str) -> float:
    x = oklab(a)
    y = oklab(b)
    return math.sqrt(sum((u - v) ** 2 for u, v in zip(x, y)))


def relative_luminance(value: str) -> float:
    r, g, b = (srgb_to_linear(c) for c in rgb01(value))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: wallpaper_profile.py IMAGE", file=sys.stderr)
        return 2

    image = Path(sys.argv[1]).expanduser()
    if not image.is_file():
        raise SystemExit(f"Wallpaper not found: {image}")

    magick = shutil.which("magick") or shutil.which("convert")
    if not magick:
        raise SystemExit("ImageMagick is required for wallpaper profiling")

    proc = subprocess.run(
        [
            magick,
            str(image),
            "-auto-orient",
            "-resize", "192x192",
            "-colors", "32",
            "-format", "%c",
            "histogram:info:-",
        ],
        check=True,
        capture_output=True,
        text=True,
        timeout=20,
    )

    pattern = re.compile(
        r"^\s*(\d+):.*?#([0-9A-Fa-f]{6})(?:[0-9A-Fa-f]{2})?\b",
        re.MULTILINE,
    )

    rows = []
    total = 0

    for count_text, raw in pattern.findall(proc.stdout):
        count = int(count_text)
        value = "#" + raw.lower()
        L, a, b = oklab(value)
        C = math.hypot(a, b)
        lum = relative_luminance(value)
        total += count
        rows.append(
            {
                "hex": value,
                "count": count,
                "L": L,
                "C": C,
                "luminance": lum,
            }
        )

    if not rows or total <= 0:
        raise SystemExit("ImageMagick returned no usable wallpaper colors")

    rows.sort(key=lambda item: item["count"], reverse=True)

    lr = lg = lb = 0.0
    mean_lum = 0.0
    mean_chroma = 0.0
    dark = 0
    bright = 0

    for row in rows:
        weight = row["count"] / total
        r, g, b = rgb01(row["hex"])
        lr += srgb_to_linear(r) * weight
        lg += srgb_to_linear(g) * weight
        lb += srgb_to_linear(b) * weight
        mean_lum += row["luminance"] * weight
        mean_chroma += row["C"] * weight

        if row["luminance"] < 0.18:
            dark += row["count"]
        if row["luminance"] > 0.72:
            bright += row["count"]

    environment = rgb_hex(
        (
            linear_to_srgb(lr),
            linear_to_srgb(lg),
            linear_to_srgb(lb),
        )
    )

    max_count = max(row["count"] for row in rows)
    ranked = []

    for row in rows:
        L = row["L"]
        C = row["C"]

        if L < 0.24 or L > 0.90 or C < 0.025:
            continue

        population = math.log1p(row["count"]) / math.log1p(max_count)
        chroma = clamp(C / 0.20)
        separation = clamp(distance(row["hex"], environment) / 0.32)
        lightness_quality = clamp(1.0 - abs(L - 0.64) / 0.44)
        highlight_penalty = clamp((L - 0.82) / 0.10)
        shadow_penalty = clamp((0.30 - L) / 0.10)

        score = (
            0.34 * chroma
            + 0.23 * separation
            + 0.20 * population
            + 0.15 * lightness_quality
            + 0.08 * (1.0 - abs(0.55 - row["luminance"]))
            - 0.22 * highlight_penalty
            - 0.14 * shadow_penalty
        )

        ranked.append(
            {
                "hex": row["hex"],
                "score": score,
                "population": row["count"] / total,
                "L": L,
                "C": C,
            }
        )

    ranked.sort(key=lambda item: item["score"], reverse=True)

    accents = []
    for item in ranked:
        if all(distance(item["hex"], old["hex"]) >= 0.055 for old in accents):
            accents.append(item)
        if len(accents) >= 5:
            break

    if not accents:
        L, a, b = oklab(environment)
        accents = [
            {
                "hex": environment,
                "score": 0.0,
                "population": 1.0,
                "L": L,
                "C": math.hypot(a, b),
            }
        ]

    representative = [
        {
            "hex": row["hex"],
            "population": row["count"] / total,
            "L": row["L"],
            "C": row["C"],
        }
        for row in rows[:12]
    ]

    print(
        json.dumps(
            {
                "ok": True,
                "image": str(image),
                "environment": environment,
                "meanLuminance": mean_lum,
                "darkFraction": dark / total,
                "brightFraction": bright / total,
                "colorfulness": clamp(mean_chroma / 0.16),
                "colors": representative,
                "accentCandidates": accents,
            },
            separators=(",", ":"),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
