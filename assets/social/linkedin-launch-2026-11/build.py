#!/usr/bin/env python3
"""Render Nyvorel's LinkedIn launch cards from real project screenshots.

Run: python3 assets/social/linkedin-launch-2026-11/build.py
The source images stay untouched. Chromium only lays them out with text and color.
"""

from __future__ import annotations

import html
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
OUTPUT = Path(__file__).resolve().parent
SCREENSHOTS = ROOT / "assets/showcase"
MOON = (ROOT / "assets/nyvorel-mark.svg").as_uri()

CARDS = [
    {
        "slug": "01-intro",
        "section": "INTRODUCING NYVOREL",
        "title": "A desktop that feels like one system.",
        "description": "An open-source Arch Linux desktop experience built with Hyprland and Quickshell.",
        "image": (OUTPUT / "desktop-context.webp").as_uri(),
        "label": "THE SHELL IN CONTEXT",
        "note": "Bar · panels · appearance · system tools",
        "accent": "#a8dce0",
        "image_position": "center",
        "image_class": "",
    },
    {
        "slug": "02-settings",
        "section": "CONNECTED CONTROLS",
        "title": "Make the next action clear.",
        "description": "Settings bring the shell's controls into one organized place, from the bar to the background.",
        "image": (SCREENSHOTS / "settings-overview.webp").as_uri(),
        "label": "SETTINGS",
        "note": "Direct controls, with room for detail",
        "accent": "#f2b9c8",
        "image_position": "center",
        "image_class": "",
    },
    {
        "slug": "03-appearance",
        "section": "APPEARANCE STUDIO",
        "title": "Let the wallpaper shape the experience.",
        "description": "Choose a color source, appearance mode, and visual character in a focused studio.",
        "image": (SCREENSHOTS / "appearance-studio.webp").as_uri(),
        "label": "APPEARANCE STUDIO",
        "note": "Wallpaper-aware palettes and modes",
        "accent": "#f2b9c8",
        "image_position": "center",
        "image_class": "",
    },
    {
        "slug": "04-operations",
        "section": "OPERATIONS CENTER",
        "title": "Make system state visible.",
        "description": "Runtime, jobs, and attention signals live in an interface you can inspect.",
        "image": (SCREENSHOTS / "operations-center.webp").as_uri(),
        "label": "OPERATIONS CENTER",
        "note": "A readable view of work and health",
        "accent": "#a8dce0",
        "image_position": "left center",
        "image_class": "operations",
    },
    {
        "slug": "05-recovery",
        "section": "BACKUP & RECOVERY",
        "title": "Recovery belongs in the product.",
        "description": "A backup-first installation path and visible recovery evidence make changes easier to trust.",
        "image": (SCREENSHOTS / "backup-recovery.webp").as_uri(),
        "label": "BACKUP & RECOVERY",
        "note": "Explore: nyvorel-web.vercel.app",
        "accent": "#f2b9c8",
        "image_position": "center",
        "image_class": "",
    },
]


def card_html(card: dict[str, str], index: int) -> str:
    value = {key: html.escape(value, quote=True) for key, value in card.items()}
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  * {{ box-sizing: border-box; }}
  html, body {{ width: 1080px; height: 1350px; margin: 0; overflow: hidden; }}
  body {{ font-family: 'Noto Sans', sans-serif; color: #f4f5f4; background: #10191c; }}
  .card {{ position: relative; width: 1080px; height: 1350px; padding: 66px 66px 54px; overflow: hidden;
    background: radial-gradient(circle at 94% 11%, color-mix(in srgb, var(--accent) 17%, transparent), transparent 32%),
      linear-gradient(154deg, #152427 0%, #10191c 55%, #0c1417 100%); --accent: {value['accent']}; }}
  .top {{ display: flex; align-items: center; justify-content: space-between; height: 67px; }}
  .brand {{ display: flex; align-items: center; gap: 12px; font-size: 23px; font-weight: 800; letter-spacing: .18em; }}
  .brand img {{ width: 52px; height: 52px; object-fit: contain; }}
  .count {{ font-family: monospace; font-size: 19px; color: #9fb4b5; letter-spacing: .1em; }}
  .rule {{ height: 1px; background: #44585b; margin: 25px 0 54px; }}
  .eyebrow {{ color: var(--accent); font-family: monospace; font-size: 19px; font-weight: 700; letter-spacing: .14em; }}
  h1 {{ margin: 23px 0 18px; max-width: 920px; font-size: 72px; line-height: 1.055; letter-spacing: -.055em; font-weight: 800; }}
  .description {{ margin: 0; max-width: 860px; color: #bbc9c9; font-size: 27px; line-height: 1.38; }}
  .shot {{ position: absolute; left: 66px; right: 66px; top: 515px; height: 578px; overflow: hidden;
    border: 1px solid #648082; border-radius: 25px; background: #26373a;
    box-shadow: 0 33px 75px rgba(0,0,0,.32), 0 0 0 8px rgba(168,220,224,.035); }}
  .shot img {{ width: 100%; height: 100%; object-fit: cover; object-position: {value['image_position']}; }}
  .shot.operations img {{ width: 160%; height: auto; max-width: none; object-fit: contain; }}
  .shot::after {{ content: ''; position: absolute; inset: 0; pointer-events: none;
    box-shadow: inset 0 0 0 1px rgba(255,255,255,.09); border-radius: 24px; }}
  .below {{ position: absolute; left: 66px; right: 66px; top: 1130px; display: flex; justify-content: space-between; gap: 25px; align-items: flex-start; }}
  .caption {{ font-family: monospace; font-size: 19px; letter-spacing: .1em; color: var(--accent); }}
  .note {{ max-width: 490px; text-align: right; color: #d3dddd; font-size: 23px; }}
  .bottom {{ position: absolute; bottom: 51px; left: 66px; right: 66px; display: flex; align-items: center; justify-content: space-between;
    border-top: 1px solid #44585b; padding-top: 22px; color: #8ea8aa; font-family: monospace; font-size: 17px; letter-spacing: .07em; }}
  .line {{ width: 72px; height: 3px; border-radius: 9px; background: var(--accent); }}
</style></head><body>
<main class="card">
  <div class="top"><div class="brand"><img src="{MOON}" alt="">NYVOREL</div><div class="count">{index:02d} / 05</div></div>
  <div class="rule"></div>
  <div class="eyebrow">{value['section']}</div>
  <h1>{value['title']}</h1>
  <p class="description">{value['description']}</p>
  <div class="shot {value['image_class']}"><img src="{value['image']}" alt=""></div>
  <div class="below"><div class="caption">{value['label']}</div><div class="note">{value['note']}</div></div>
  <div class="bottom"><span>ARCH LINUX · HYPRLAND · QUICKSHELL</span><span class="line"></span></div>
</main></body></html>"""


def main() -> None:
    for index, card in enumerate(CARDS, 1):
        source = OUTPUT / f"{card['slug']}.html"
        target = OUTPUT / f"{card['slug']}.png"
        source.write_text(card_html(card, index), encoding="utf-8")
        subprocess.run(
            [
                "chromium", "--headless", "--no-sandbox", "--disable-gpu",
                f"--user-data-dir=/tmp/nyvorel-linkedin-chromium-{index}",
                "--hide-scrollbars", "--force-device-scale-factor=1",
                "--window-size=1080,1350", "--virtual-time-budget=1500",
                f"--screenshot={target}", source.as_uri(),
            ],
            check=True,
        )
        print(target)


if __name__ == "__main__":
    main()
