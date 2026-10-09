#!/usr/bin/env python3
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
from contextlib import contextmanager
import math
from copy import deepcopy
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse

HOME = Path.home()
XDG_CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config"))
XDG_STATE = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state"))
XDG_CACHE = Path(os.environ.get("XDG_CACHE_HOME", HOME / ".cache"))

NYVOREL_CONFIG = XDG_CONFIG / "nyvorel/config.json"
STUDIO_STATE = XDG_CONFIG / "nyvorel/appearance-studio.json"
NYVOREL_DIR = XDG_CONFIG / "quickshell/nyvorel"
SWITCHWALL = NYVOREL_DIR / "scripts/colors/switchwall.sh"
SCHEME_DETECTOR = NYVOREL_DIR / "scripts/colors/scheme_for_image.py"
PROBE = NYVOREL_DIR / "scripts/appearance-studio/palette_probe.py"
WALLPAPER_PROFILE = NYVOREL_DIR / "scripts/appearance-studio/wallpaper_profile.py"
GENERATED = XDG_STATE / "quickshell/user/generated"
COLORS_JSON = GENERATED / "colors.json"
MATERIAL_SCSS = GENERATED / "material_colors.scss"
COLOR_TXT = GENERATED / "color.txt"
WALLPAPER_TXT = GENERATED / "wallpaper/path.txt"
APPLYCOLOR = NYVOREL_DIR / "scripts/colors/applycolor.sh"
GLASS_RUNTIME = HOME / ".local/bin/nyvorel-glass-runtime"
FLUID_RUNTIME = HOME / ".local/bin/nyvorel-fluid-runtime"  # fluid-interface-v1
EDITOR_COLOR_SCRIPT = NYVOREL_DIR / "scripts/colors/code/material-code-set-color.sh"
QT_WRAPPER = XDG_CONFIG / "matugen/templates/kde/kde-material-you-colors-wrapper.sh"
VIDEO_RESTORE_SCRIPT = XDG_CONFIG / "nyvorel/video-wallpaper-restore.sh"
HYPR_CUSTOM_GENERAL = XDG_CONFIG / "hypr/custom/appearance-runtime.conf"
HYPR_CUSTOM_RULES = HYPR_CUSTOM_GENERAL
KITTY_CONFIG = XDG_CONFIG / "kitty/kitty.conf"
TERMINAL_RUNTIME_FILES = [
    HOME / ".config/kitty/nyvorel-dynamic-theme.conf",
    HOME / ".config/starship.toml",
    HOME / ".config/kitty/tab_bar.py",
    HOME / ".config/fish/conf.d/99-nyvorel-dynamic-theme.fish",
    HOME / ".local/state/nyvorel/terminal-startup-overlay.fish",
]
VIDEO_THUMBNAIL_DIR = XDG_CONFIG / "hypr/custom/scripts/mpvpaper_thumbnails"
VIDEO_PREVIEW_DIR = XDG_CACHE / "nyvorel-appearance-studio/video-previews"
VIDEO_OPTS = "no-audio loop hwdec=auto scale=bilinear interpolation=no video-sync=display-resample panscan=1.0 video-scale-x=1.0 video-scale-y=1.0 video-align-x=0.5 video-align-y=0.5 load-scripts=no"
PREVIEW_DIR = XDG_CACHE / "nyvorel-appearance-studio/preview"
PREVIEW_TIMEOUT_SECONDS = 15
LOCK_FILE = XDG_CACHE / "nyvorel-appearance-studio/appearance-studio.lock"
STATE_VERSION = 4
STUDIO_VERSION = "0.3.2"

HYBRID_SURFACE_ROLES = {
    "background", "on_background",
    "surface", "surface_dim", "surface_bright",
    "surface_container_lowest", "surface_container_low", "surface_container",
    "surface_container_high", "surface_container_highest",
    "surface_variant", "on_surface", "on_surface_variant",
    "outline", "outline_variant",
    "inverse_surface", "inverse_on_surface",
    "shadow", "scrim",
}

SCHEMES = [
    ("auto", "Auto"),
    ("scheme-tonal-spot", "Balanced"),
    ("scheme-fidelity", "Faithful"),
    ("scheme-content", "Natural"),
    ("scheme-expressive", "Vibrant"),
    ("scheme-neutral", "Minimal"),
    ("scheme-monochrome", "Monochrome"),
    ("scheme-rainbow", "Varied"),
    ("scheme-fruit-salad", "Playful"),
]

# BEGIN appearance-modes-minimal-v7
MODES = [
    ("light", "Light"),
    ("dark", "Dark"),
    ("dim", "Dim"),
    ("oled", "OLED"),
    ("high-contrast", "High Contrast"),
]

MATERIAL_ROLES = [
    "background", "error", "error_container", "inverse_on_surface",
    "inverse_primary", "inverse_surface", "on_background", "on_error",
    "on_error_container", "on_primary", "on_primary_container",
    "on_primary_fixed", "on_primary_fixed_variant", "on_secondary",
    "on_secondary_container", "on_secondary_fixed",
    "on_secondary_fixed_variant", "on_surface", "on_surface_variant",
    "on_tertiary", "on_tertiary_container", "on_tertiary_fixed",
    "on_tertiary_fixed_variant", "outline", "outline_variant", "primary",
    "primary_container", "primary_fixed", "primary_fixed_dim", "scrim",
    "secondary", "secondary_container", "secondary_fixed",
    "secondary_fixed_dim", "shadow", "surface", "surface_bright",
    "surface_container", "surface_container_high", "surface_container_highest",
    "surface_container_low", "surface_container_lowest", "surface_dim",
    "surface_tint", "surface_variant", "tertiary", "tertiary_container",
    "tertiary_fixed", "tertiary_fixed_dim",
]
REQUIRED_PREVIEW_ROLES = {
    "background", "on_background", "surface", "on_surface", "primary",
    "on_primary", "primary_container", "on_primary_container", "secondary",
    "secondary_container", "tertiary", "tertiary_container", "outline",
    "outline_variant",
}

PRESETS = [{'id': 'midnight',
  'name': 'Cobalt',
  'seed': '#5368B7',
  'scheme': 'scheme-tonal-spot',
  'description': 'Deep tailored blue with crisp, confident contrast.'},
 {'id': 'arctic',
  'name': 'Fjord',
  'seed': '#4F7E8C',
  'scheme': 'scheme-tonal-spot',
  'description': 'Cool blue-gray with quiet, architectural surfaces.'},
 {'id': 'ocean',
  'name': 'Teal',
  'seed': '#3F7C72',
  'scheme': 'scheme-tonal-spot',
  'description': 'Refined blue-green with a calm modern character.'},
 {'id': 'evergreen',
  'name': 'Pine',
  'seed': '#50715D',
  'scheme': 'scheme-tonal-spot',
  'description': 'Deep natural green with restrained, premium neutrals.'},
 {'id': 'forest',
  'name': 'Olive',
  'seed': '#7A7B4F',
  'scheme': 'scheme-content',
  'description': 'Muted olive with organic warmth and editorial balance.'},
 {'id': 'ember',
  'name': 'Amber',
  'seed': '#B77A3D',
  'scheme': 'scheme-tonal-spot',
  'description': 'Burnished amber with warm, sophisticated accents.'},
 {'id': 'sandstone',
  'name': 'Terracotta',
  'seed': '#A85F4E',
  'scheme': 'scheme-content',
  'description': 'Earthy terracotta with rich warmth and controlled chroma.'},
 {'id': 'rosewood',
  'name': 'Rosewood',
  'seed': '#8E5367',
  'scheme': 'scheme-fidelity',
  'description': 'Smoky wine-rose with grounded, elegant depth.'},
 {'id': 'amethyst',
  'name': 'Plum',
  'seed': '#6E5686',
  'scheme': 'scheme-tonal-spot',
  'description': 'Deep plum with subtle creative energy and soft neutrals.'},
 {'id': 'graphite',
  'name': 'Graphite',
  'seed': '#7B8189',
  'scheme': 'scheme-monochrome',
  'description': 'Balanced cool graphite for a focused, low-noise desktop.'}]

def _radius_patch(global_value: int, **roles: tuple[bool, int]) -> dict[str, Any]:
    patch: dict[str, Any] = {
        "appearance.geometry.radius.global": global_value,
    }
    for role, (follow_global, value) in roles.items():
        patch[f"appearance.geometry.radius.{role}.followGlobal"] = follow_global
        patch[f"appearance.geometry.radius.{role}.value"] = value
    return patch


UI_PROFILES: dict[str, dict[str, Any]] = {
    "default": {
        "name": "Default",
        "description": "Nyvorel defaults",
        "patch": {
            "appearance.interfaceStyle": "default",
            **_radius_patch(
                17,
                window=(False, 8),
                bar=(False, 8),
                modal=(False, 23),
                sidebar=(False, 23),
                popup=(True, 17),
                card=(True, 17),
                control=(False, 12),
                screen=(False, 8),
            ),
            "appearance.transparency.enable": False,
            "appearance.transparency.automatic": True,
            "appearance.transparency.backgroundTransparency": 0.0,
            "appearance.transparency.contentTransparency": 0.0,
            "appearance.extraBackgroundTint": True,
            "bar.cornerStyle": 1,
            "bar.floatStyleShadow": True,
            "bar.borderless": False,
            "bar.showBackground": True,
            "bar.verbose": True,
        },
    },
    # inlay-v2-foundation
    "inlay": {
        "name": "Inlay",
        "description": "Structured matte interface with embedded panels, sharp borders and crisp geometry",
        "patch": {
            "appearance.interfaceStyle": "inlay",
            **_radius_patch(
                0,
                window=(False, 0),
                bar=(False, 0),
                modal=(False, 0),
                sidebar=(False, 0),
                popup=(False, 0),
                card=(False, 0),
                control=(False, 0),
                screen=(False, 0),
            ),
            # Matte contract: no transparency and no automatic glass behavior.
            "appearance.transparency.enable": False,
            "appearance.transparency.automatic": False,
            "appearance.transparency.backgroundTransparency": 0.0,
            "appearance.transparency.contentTransparency": 0.0,
            # Keep the proven wallpaper-derived material engine as Inlay's color base.
            "appearance.extraBackgroundTint": True,
            # Preserve the shell's existing spacing/margins; only shape/shadow changes here.
            "bar.cornerStyle": 1,
            "bar.floatStyleShadow": False,
            "bar.borderless": False,
            "bar.showBackground": True,
            "bar.verbose": True,
        },
    },
    # prism-interface-v1
    "prism": {
        "name": "Prism",
        "description": "Spatial interface built from detached surfaces, layered depth and responsive motion",
        "patch": {
            "appearance.interfaceStyle": "prism",
            **_radius_patch(
                17,
                window=(False, 8),
                bar=(False, 8),
                modal=(False, 23),
                sidebar=(False, 23),
                popup=(True, 17),
                card=(True, 17),
                control=(False, 12),
                screen=(False, 8),
            ),
            "appearance.transparency.enable": False,
            "appearance.transparency.automatic": False,
            "appearance.transparency.backgroundTransparency": 0.0,
            "appearance.transparency.contentTransparency": 0.0,
            "appearance.extraBackgroundTint": False,
            "bar.cornerStyle": 1,
            "bar.floatStyleShadow": True,
            "bar.borderless": False,
            "bar.showBackground": True,
            "bar.verbose": True,
        },
    },


    # fluid-interface-v1
    # Caelestia base=0.6 / layers=0.2 opacity maps to II transparency
    # amounts 0.40 / 0.80.
    "fluid": {
        "name": "Fluid",
        "description": "Caelestia-inspired translucent HUD with wireframe depth",
        "patch": {
            "appearance.interfaceStyle": "fluid",
            **_radius_patch(
                8,
                window=(False, 8),
                bar=(False, 8),
                modal=(False, 10),
                sidebar=(False, 10),
                popup=(False, 8),
                card=(False, 6),
                control=(False, 4),
                screen=(False, 8),
            ),
            "appearance.transparency.enable": True,
            "appearance.transparency.automatic": False,
            "appearance.transparency.backgroundTransparency": 0.40,
            "appearance.transparency.contentTransparency": 0.80,
            "appearance.extraBackgroundTint": False,
            "bar.cornerStyle": 1,
            "bar.floatStyleShadow": False,
            "bar.borderless": False,
            "bar.showBackground": True,
            "bar.verbose": True,
        },
    },


    "floating": {
        "name": "Floating",
        "description": "Elevated floating bar with subtle transparency",
        "patch": {
            "appearance.interfaceStyle": "floating",
            **_radius_patch(
                17,
                window=(False, 12),
                bar=(False, 24),
                modal=(False, 23),
                sidebar=(False, 23),
                popup=(True, 17),
                card=(True, 17),
                control=(False, 12),
                screen=(False, 8),
            ),
            "appearance.transparency.enable": True,
            "appearance.transparency.automatic": False,
            "appearance.transparency.backgroundTransparency": 0.10,
            "appearance.transparency.contentTransparency": 0.72,
            "appearance.extraBackgroundTint": True,
            "bar.cornerStyle": 1,
            "bar.floatStyleShadow": True,
            "bar.borderless": False,
            "bar.showBackground": True,
            "bar.verbose": True,
        },
    },
    "solid": {
        "name": "Solid",
        "description": "Opaque, quiet surfaces with maximum readability",
        "patch": {
            "appearance.interfaceStyle": "solid",
            **_radius_patch(
                8,
                window=(False, 8),
                bar=(False, 8),
                modal=(False, 12),
                sidebar=(False, 12),
                popup=(True, 8),
                card=(True, 8),
                control=(False, 8),
                screen=(False, 0),
            ),
            "appearance.transparency.enable": False,
            "appearance.transparency.automatic": False,
            "appearance.transparency.backgroundTransparency": 0.0,
            "appearance.transparency.contentTransparency": 0.0,
            "appearance.extraBackgroundTint": False,
            "bar.cornerStyle": 0,
            "bar.floatStyleShadow": False,
            "bar.borderless": False,
            "bar.showBackground": True,
            "bar.verbose": True,
        },
    },
    "minimal": {
        "name": "Minimal",
        "description": "Simple rectangular bar and reduced visual noise",
        "patch": {
            "appearance.interfaceStyle": "minimal",
            **_radius_patch(
                0,
                window=(False, 0),
                bar=(False, 0),
                modal=(False, 0),
                sidebar=(False, 0),
                popup=(True, 0),
                card=(True, 0),
                control=(False, 0),
                screen=(False, 0),
            ),
            "appearance.transparency.enable": False,
            "appearance.transparency.automatic": False,
            "appearance.transparency.backgroundTransparency": 0.0,
            "appearance.transparency.contentTransparency": 0.0,
            "appearance.extraBackgroundTint": False,
            "bar.cornerStyle": 2,
            "bar.floatStyleShadow": False,
            "bar.borderless": True,
            "bar.showBackground": True,
            "bar.verbose": False,
        },
    },
}

EDITOR_SETTINGS = [
    XDG_CONFIG / "Code/User/settings.json",
    XDG_CONFIG / "VSCodium/User/settings.json",
    XDG_CONFIG / "Code - OSS/User/settings.json",
    XDG_CONFIG / "Code - Insiders/User/settings.json",
    XDG_CONFIG / "Cursor/User/settings.json",
    XDG_CONFIG / "Antigravity/User/settings.json",
]

TARGET_FILES = {
    "shell": [COLORS_JSON],
    "hyprland": [XDG_CONFIG / "hypr/hyprland/colors.conf"],
    "hyprlock": [XDG_CONFIG / "hypr/hyprlock/colors.conf"],
    "fuzzel": [XDG_CONFIG / "fuzzel/fuzzel_theme.ini"],
    "gtk": [XDG_CONFIG / "gtk-3.0/gtk.css", XDG_CONFIG / "gtk-4.0/gtk.css"],
    "editors": EDITOR_SETTINGS,
}

RADIUS_DEFAULTS: dict[str, Any] = {
    "global": 17,
    "window": {"followGlobal": False, "value": 8},
    "bar": {"followGlobal": False, "value": 8},
    "modal": {"followGlobal": False, "value": 23},
    "sidebar": {"followGlobal": False, "value": 23},
    "popup": {"followGlobal": True, "value": 17},
    "card": {"followGlobal": True, "value": 17},
    "control": {"followGlobal": False, "value": 12},
    "screen": {"followGlobal": False, "value": 8},
}
RADIUS_ROLES = ("window", "bar", "modal", "sidebar", "popup", "card", "control", "screen")


def _local_path(value: str) -> Path:
    raw = str(value or "")
    if raw.startswith("file://"):
        raw = unquote(urlparse(raw).path)
    return Path(raw).expanduser()


def _read_json(path: Path, default: Any) -> Any:
    try:
        return json.loads(path.read_text())
    except Exception:
        return deepcopy(default)


def _write_json(path: Path, data: Any) -> None:
    rendered = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    if path.is_file() and path.read_text() == rendered:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(rendered)
    tmp.replace(path)


@contextmanager
def _mutation_lock(timeout: float = 12.0):
    """Serialize every state-changing Appearance Studio operation."""
    LOCK_FILE.parent.mkdir(parents=True, exist_ok=True)
    handle = LOCK_FILE.open("a+")
    deadline = time.monotonic() + timeout
    try:
        while True:
            try:
                fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise RuntimeError("Appearance Studio is busy; try again in a moment")
                time.sleep(0.05)
        yield
    finally:
        try:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
        except Exception:
            pass
        handle.close()


def _is_hyprland_session() -> bool:
    desktop = os.environ.get("XDG_CURRENT_DESKTOP", "").lower()
    return "hyprland" in desktop or bool(os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"))


def _default_state() -> dict[str, Any]:
    cfg = _read_json(NYVOREL_CONFIG, {})
    theme_cfg = cfg.get("appearance", {}).get("wallpaperTheming", {})
    palette = cfg.get("appearance", {}).get("palette", {})
    mode = _system_mode()
    return {
        "version": STATE_VERSION,
        "active": {
            "source": "wallpaper",
            "preset": "",
            "seed": "",
            "scheme": palette.get("type", "auto") or "auto",
            "mode": mode,
            "wallpaper": cfg.get("background", {}).get("wallpaperPath", ""),
            "uiProfile": _detect_ui_profile(cfg),
        },
        "targets": {
            "shell": True,
            "hyprland": True,
            "hyprlock": True,
            "gtk": True,
            "fuzzel": True,
            # II's bundled KDE bridge attempts to talk to KWin. On Hyprland
            # keep it opt-in to avoid the known org.kde.KWin DBus failure.
            "qt": bool(theme_cfg.get("enableQtApps", True)) and not _is_hyprland_session(),
            "terminal": bool(theme_cfg.get("enableTerminal", True)),
            "editors": True,
        },
        "activeUi": _config_snapshot(),
        "favorites": [],
        "history": [],
        "preview": None,
    }


def _load_state() -> dict[str, Any]:
    default = _default_state()
    state = _read_json(STUDIO_STATE, default)
    for key, value in default.items():
        state.setdefault(key, deepcopy(value))
    for key, value in default["targets"].items():
        state["targets"].setdefault(key, value)
    if not isinstance(state.get("activeUi"), dict):
        state["activeUi"] = _config_snapshot()
    state["version"] = STATE_VERSION
    return state


def _save_state(state: dict[str, Any]) -> None:
    _write_json(STUDIO_STATE, state)


def _system_mode() -> str:
    try:
        result = subprocess.run(
            ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"],
            check=False, capture_output=True, text=True, timeout=2,
        ).stdout
        return "dark" if "dark" in result else "light"
    except Exception:
        return "dark"


def _get_nested(data: dict[str, Any], dotted: str, default: Any = None) -> Any:
    current: Any = data
    for part in dotted.split("."):
        if not isinstance(current, dict) or part not in current:
            return default
        current = current[part]
    return current


def _set_nested(data: dict[str, Any], dotted: str, value: Any) -> None:
    parts = dotted.split(".")
    current = data
    for part in parts[:-1]:
        if not isinstance(current.get(part), dict):
            current[part] = {}
        current = current[part]
    current[parts[-1]] = value


def _ensure_radius_geometry(cfg: dict[str, Any]) -> dict[str, Any]:
    appearance = cfg.setdefault("appearance", {})
    geometry = appearance.setdefault("geometry", {})
    radius = geometry.setdefault("radius", {})
    if radius.get("global") is None:
        radius["global"] = int(RADIUS_DEFAULTS["global"])
    for role in RADIUS_ROLES:
        default = RADIUS_DEFAULTS[role]
        current = radius.get(role)
        if not isinstance(current, dict):
            current = {}
            radius[role] = current
        current.setdefault("followGlobal", bool(default["followGlobal"]))
        current.setdefault("value", int(default["value"]))
    return cfg


def _resolved_radius(cfg: dict[str, Any], role: str) -> int:
    _ensure_radius_geometry(cfg)
    radius = cfg["appearance"]["geometry"]["radius"]
    global_value = max(0, min(48, int(radius.get("global", 17))))
    if role == "global":
        return global_value
    entry = radius.get(role, {})
    if bool(entry.get("followGlobal", False)):
        return global_value
    return max(0, min(48, int(entry.get("value", RADIUS_DEFAULTS.get(role, {}).get("value", global_value)))))


def _replace_managed_hypr_radius(text: str, value: int) -> str:
    begin = "# >>> Appearance Studio: window radius >>>"
    end = "# <<< Appearance Studio: window radius <<<"
    block = (
        f"{begin}\n"
        "decoration {\n"
        f"    rounding = {int(value)}\n"
        "}\n"
        f"{end}"
    )
    pattern = re.compile(re.escape(begin) + r".*?" + re.escape(end), re.S)
    if pattern.search(text):
        return pattern.sub(block, text)
    suffix = "" if not text or text.endswith("\n") else "\n"
    return text + suffix + ("\n" if text else "") + block + "\n"


def _sync_hyprland_window_radius(cfg: dict[str, Any] | None = None, *, persist: bool) -> None:
    cfg = deepcopy(cfg if cfg is not None else _read_json(NYVOREL_CONFIG, {}))
    _ensure_radius_geometry(cfg)
    value = _resolved_radius(cfg, "window")

    if persist:
        try:
            current = HYPR_CUSTOM_GENERAL.read_text() if HYPR_CUSTOM_GENERAL.is_file() else ""
            updated = _replace_managed_hypr_radius(current, value)
            if updated != current:
                HYPR_CUSTOM_GENERAL.parent.mkdir(parents=True, exist_ok=True)
                HYPR_CUSTOM_GENERAL.write_text(updated)
        except Exception as exc:
            raise RuntimeError(f"Could not persist Hyprland window radius: {exc}") from exc

    if _is_hyprland_session() and shutil.which("hyprctl"):
        proc = subprocess.run(
            ["hyprctl", "keyword", "decoration:rounding", str(value)],
            check=False, capture_output=True, text=True, timeout=5,
        )
        if proc.returncode != 0 and persist:
            details = (proc.stderr or proc.stdout).strip()
            raise RuntimeError(f"Could not apply Hyprland window radius: {details[-500:]}")


LEGACY_UI_PROFILE_ALIASES: dict[str, str] = {
    "mica": "inlay",
}


def _detect_ui_profile(cfg: dict[str, Any] | None = None) -> str:
    cfg = cfg or _read_json(NYVOREL_CONFIG, {})

    # First prefer the new exact profile contract, including interface identity.
    for profile_id, profile in UI_PROFILES.items():
        patch = profile.get("patch", {})
        if patch and all(_get_nested(cfg, key) == value for key, value in patch.items()):
            return profile_id

    # Backward compatibility for configs created before prism-v2-foundation.
    # Only use legacy matching while the explicit marker is absent.
    if not _get_nested(cfg, "appearance.interfaceStyle"):
        for profile_id, profile in UI_PROFILES.items():
            patch = {
                key: value
                for key, value in profile.get("patch", {}).items()
                if key != "appearance.interfaceStyle"
            }
            if patch and all(_get_nested(cfg, key) == value for key, value in patch.items()):
                return profile_id

    return "custom"


def _config_snapshot() -> dict[str, Any]:
    cfg = _read_json(NYVOREL_CONFIG, {})
    _ensure_radius_geometry(cfg)
    keys = [
        "appearance.interfaceStyle",
        "appearance.extraBackgroundTint",
        "appearance.fakeScreenRounding",
        "appearance.transparency.enable",
        "appearance.transparency.automatic",
        "appearance.transparency.backgroundTransparency",
        "appearance.transparency.contentTransparency",
        "bar.cornerStyle",
        "bar.floatStyleShadow",
        "bar.borderless",
        "bar.showBackground",
        "bar.verbose",
        "bar.bottom",
        "bar.vertical",
        "background.parallax.enableWorkspace",
        "background.parallax.enableSidebar",
        "appearance.motion.reduced",
        "appearance.motion.scale",
        "appearance.motion.expressive",
        "appearance.geometry.radius.global",
        "appearance.geometry.radius.window.followGlobal",
        "appearance.geometry.radius.window.value",
        "appearance.geometry.radius.bar.followGlobal",
        "appearance.geometry.radius.bar.value",
        "appearance.geometry.radius.modal.followGlobal",
        "appearance.geometry.radius.modal.value",
        "appearance.geometry.radius.sidebar.followGlobal",
        "appearance.geometry.radius.sidebar.value",
        "appearance.geometry.radius.popup.followGlobal",
        "appearance.geometry.radius.popup.value",
        "appearance.geometry.radius.card.followGlobal",
        "appearance.geometry.radius.card.value",
        "appearance.geometry.radius.control.followGlobal",
        "appearance.geometry.radius.control.value",
        "appearance.geometry.radius.screen.followGlobal",
        "appearance.geometry.radius.screen.value",
    ]
    return {k: _get_nested(cfg, k) for k in keys}


def _restore_config_snapshot(snapshot: dict[str, Any]) -> None:
    cfg = _read_json(NYVOREL_CONFIG, {})
    for key, value in snapshot.items():
        if value is not None:
            _set_nested(cfg, key, value)
    _write_json(NYVOREL_CONFIG, cfg)


def _apply_ui_snapshot_to_cfg(cfg: dict[str, Any], snapshot: dict[str, Any] | None) -> dict[str, Any]:
    if not snapshot:
        return cfg
    allowed = set(_config_snapshot().keys())
    for key, value in snapshot.items():
        if key in allowed and value is not None:
            _set_nested(cfg, key, value)
    return cfg


def _current_wallpaper(cfg: dict[str, Any] | None = None) -> str:
    cfg = cfg or _read_json(NYVOREL_CONFIG, {})
    return str(cfg.get("background", {}).get("wallpaperPath", "") or "")


def _is_video(path: str) -> bool:
    return _local_path(path).suffix.lower() in {".mp4", ".webm", ".mkv", ".avi", ".mov"}


def _extract_video_frame(video: str, *, preview: bool) -> str:
    video_path = _local_path(video)
    if not video_path.is_file():
        raise RuntimeError(f"Video wallpaper not found: {video_path}")
    if not shutil.which("ffmpeg"):
        raise RuntimeError("ffmpeg is required for video wallpaper previews")

    directory = VIDEO_PREVIEW_DIR if preview else VIDEO_THUMBNAIL_DIR
    directory.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256(str(video_path).encode()).hexdigest()[:12]
    output = directory / f"{video_path.stem}-{digest}.jpg"
    if output.is_file() and output.stat().st_size > 0:
        return str(output)

    proc = subprocess.run(
        ["ffmpeg", "-y", "-ss", "0", "-i", str(video_path), "-frames:v", "1", str(output)],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    if proc.returncode != 0 or not output.is_file():
        raise RuntimeError(f"Could not extract a frame from video wallpaper: {(proc.stderr or '').strip()[-500:]}")
    return str(output)


def _source_image_for_wallpaper(wallpaper: str, cfg: dict[str, Any], *, preview: bool) -> str:
    path = str(_local_path(wallpaper)) if wallpaper else ""
    if not path:
        return ""
    if not _is_video(path):
        return path

    # Reuse the configured thumbnail only when it belongs to the active video.
    configured = str(cfg.get("background", {}).get("wallpaperPath", "") or "")
    thumb = str(cfg.get("background", {}).get("thumbnailPath", "") or "")
    if configured == path and thumb and _local_path(thumb).is_file():
        return str(_local_path(thumb))
    return _extract_video_frame(path, preview=preview)


def _source_color_from_image(path: str) -> str:
    p = _local_path(path)
    if not p.is_file():
        raise RuntimeError(f"Wallpaper not found: {p}")

    # Matugen 4.2 exposes the exact candidate colors without opening the picker.
    try:
        proc = subprocess.run(
            ["matugen", "image-colors", str(p)],
            check=False, capture_output=True, text=True, timeout=15,
        )
        colors = re.findall(r"#[0-9A-Fa-f]{6}", proc.stdout + "\n" + proc.stderr)
        if colors:
            return colors[0].lower()
    except Exception:
        pass

    # Fallback to the same Material quantizer used by the II Python environment.
    py = Path(os.path.expanduser(os.environ.get("NYVOREL_VIRTUAL_ENV", "~/.local/state/quickshell/.venv"))) / "bin/python"
    if py.is_file() and PROBE.is_file():
        proc = subprocess.run(
            [str(py), str(PROBE), "source", str(p)],
            check=False, capture_output=True, text=True, timeout=20,
        )
        colors = re.findall(r"#[0-9A-Fa-f]{6}", proc.stdout)
        if colors:
            return colors[0].lower()

    # Do not silently fall back to a whole-image average. An average color is
    # often a poor Material source for wallpapers with dark environments plus
    # small vivid accents. If both real Material extractors fail, surface the
    # failure so the user can fix the pipeline instead of previewing a lie.
    raise RuntimeError("Could not extract a Material source color from the wallpaper")


def _resolve_scheme(requested: str, wallpaper: str) -> str:
    if requested != "auto":
        return requested
    path = _local_path(wallpaper)
    py = Path(os.path.expanduser(os.environ.get(
        "NYVOREL_VIRTUAL_ENV", "~/.local/state/quickshell/.venv",
    ))) / "bin/python"
    if path.is_file() and SCHEME_DETECTOR.is_file() and py.is_file():
        env = os.environ.copy()
        proc = subprocess.run(
            [str(py), str(SCHEME_DETECTOR), str(path)],
            check=False, capture_output=True, text=True, timeout=15, env=env,
        )
        candidate = proc.stdout.strip()
        allowed = {s[0] for s in SCHEMES if s[0] != "auto"}
        if candidate in allowed:
            return candidate
    return "scheme-tonal-spot"


def _image_luminance(path: str) -> float:
    p = _local_path(path)
    if not p.is_file():
        return 0.25
    try:
        proc = subprocess.run(
            ["magick", str(p), "-auto-orient", "-colorspace", "Gray", "-resize", "1x1!", "-format", "%[fx:mean]", "info:"],
            check=False, capture_output=True, text=True, timeout=10,
        )
        return float(proc.stdout.strip())
    except Exception:
        return 0.25


def _resolve_base_mode(mode: str, wallpaper: str) -> str:
    # Stored id "auto" means System: follow the desktop preference.
    if mode == "auto":
        return _system_mode()

    # Adaptive is a separate wallpaper-aware choice.
    # It uses luminance distribution from Appearance Intelligence when
    # available and intentionally stays Dark unless the image is clearly bright.
    if mode == "adaptive":
        try:
            profile_fn = globals().get("_wallpaper_profile")
            if callable(profile_fn) and wallpaper:
                profile = profile_fn(wallpaper)
                mean = float(profile.get("meanLuminance", 0.35))
                dark_fraction = float(profile.get("darkFraction", 0.0))
                bright_fraction = float(profile.get("brightFraction", 0.0))

                light_evidence = (
                    mean >= 0.52
                    and dark_fraction <= 0.38
                    and (bright_fraction >= 0.18 or mean >= 0.62)
                )
                return "light" if light_evidence else "dark"
        except Exception:
            pass

        # Compatibility fallback if semantic profiling is unavailable.
        try:
            luminance_fn = globals().get("_wallpaper_luminance")
            if callable(luminance_fn) and wallpaper:
                return "light" if float(luminance_fn(wallpaper)) >= 0.58 else "dark"
        except Exception:
            pass
        return "dark"

    # These are dark treatments / accessibility treatments.
    if mode in {"oled", "dim", "high-contrast"}:
        return "dark"

    return mode if mode in {"dark", "light"} else "dark"


def _hex_scale(value: str, factor: float) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"#[0-9A-Fa-f]{6}", value):
        return value
    nums = [int(value[i:i+2], 16) for i in (1, 3, 5)]
    nums = [max(0, min(255, round(v * factor))) for v in nums]
    return "#" + "".join(f"{v:02x}" for v in nums)


# BEGIN appearance-mode-direction-v5

def _appearance_rgb(value: str) -> tuple[float, float, float]:
    h = value.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def _appearance_srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _appearance_linear_to_srgb(c: float) -> float:
    c = max(0.0, min(1.0, c))
    return 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055


def _appearance_oklab(value: str) -> tuple[float, float, float]:
    r, g, b = (_appearance_srgb_to_linear(c) for c in _appearance_rgb(value))
    l = 0.4122214708*r + 0.5363325363*g + 0.0514459929*b
    m = 0.2119034982*r + 0.6806995451*g + 0.1073969566*b
    s = 0.0883024619*r + 0.2817188376*g + 0.6299787005*b
    l_, m_, s_ = l ** (1/3), m ** (1/3), s ** (1/3)
    return (
        0.2104542553*l_ + 0.7936177850*m_ - 0.0040720468*s_,
        1.9779984951*l_ - 2.4285922050*m_ + 0.4505937099*s_,
        0.0259040371*l_ + 0.7827717662*m_ - 0.8086757660*s_,
    )


def _appearance_oklab_hex(L: float, a: float, b: float) -> str:
    l_ = L + 0.3963377774*a + 0.2158037573*b
    m_ = L - 0.1055613458*a - 0.0638541728*b
    s_ = L - 0.0894841775*a - 1.2914855480*b
    l, m, s = l_**3, m_**3, s_**3

    r = +4.0767416621*l - 3.3077115913*m + 0.2309699292*s
    g = -1.2684380046*l + 2.6097574011*m - 0.3413193965*s
    bl = -0.0041960863*l - 0.7034186147*m + 1.7076147010*s

    rgb = [_appearance_linear_to_srgb(c) for c in (r, g, bl)]
    return "#" + "".join(
        f"{round(max(0.0, min(1.0, c)) * 255):02x}"
        for c in rgb
    )


def _appearance_perceptual_dim(value: str) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"#[0-9A-Fa-f]{6}", value):
        return value
    L, a, b = _appearance_oklab(value)

    # Reduce perceptual lightness, preserve hue, slightly restrain chroma.
    return _appearance_oklab_hex(
        max(0.025, L * 0.78),
        a * 0.96,
        b * 0.96,
    )


def _appearance_relative_luminance(value: str) -> float:
    r, g, b = (_appearance_srgb_to_linear(c) for c in _appearance_rgb(value))
    return 0.2126*r + 0.7152*g + 0.0722*b


def _appearance_contrast(a: str, b: str) -> float:
    l1 = _appearance_relative_luminance(a)
    l2 = _appearance_relative_luminance(b)
    return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)


def _appearance_ensure_contrast(
    colors: dict[str, Any],
    on_role: str,
    base_role: str,
    minimum: float = 7.0,
) -> None:
    fg = colors.get(on_role)
    bg = colors.get(base_role)
    if not (
        isinstance(fg, str)
        and isinstance(bg, str)
        and re.fullmatch(r"#[0-9A-Fa-f]{6}", fg)
        and re.fullmatch(r"#[0-9A-Fa-f]{6}", bg)
    ):
        return

    if _appearance_contrast(fg, bg) >= minimum:
        return

    white = "#ffffff"
    black = "#000000"
    colors[on_role] = (
        white
        if _appearance_contrast(white, bg) >= _appearance_contrast(black, bg)
        else black
    )


def _apply_special_mode_colors(colors: dict[str, Any], mode: str) -> dict[str, Any]:
    result = deepcopy(colors)
    if mode == "oled":
        result.update({
            "background": "#000000", "surface": "#000000", "surface_dim": "#000000",
            "surface_container_lowest": "#000000", "surface_container_low": "#030303",
            "surface_container": "#070707", "surface_container_high": "#0c0c0c",
            "surface_container_highest": "#121212", "surface_bright": "#1a1a1a",
        })
    elif mode == "dim":
        for key in [
            "background", "surface", "surface_dim", "surface_bright", "surface_variant",
            "surface_container_lowest", "surface_container_low", "surface_container",
            "surface_container_high", "surface_container_highest",
        ]:
            if key in result:
                result[key] = _appearance_perceptual_dim(result[key])
    elif mode == "high-contrast":
        result.update({
            "background": "#000000", "surface": "#000000", "surface_dim": "#000000",
            "surface_container_lowest": "#000000", "surface_container_low": "#080808",
            "surface_container": "#101010", "surface_container_high": "#181818",
            "surface_container_highest": "#222222", "on_background": "#ffffff",
            "on_surface": "#ffffff", "on_surface_variant": "#f2f2f2",
            "outline": "#f0f0f0", "outline_variant": "#8c8c8c",
        })
    if mode == "high-contrast":
        for on_role, base_role in [
            ("on_background", "background"),
            ("on_surface", "surface"),
            ("on_surface_variant", "surface_variant"),
            ("on_primary", "primary"),
            ("on_primary_container", "primary_container"),
            ("on_secondary", "secondary"),
            ("on_secondary_container", "secondary_container"),
            ("on_tertiary", "tertiary"),
            ("on_tertiary_container", "tertiary_container"),
            ("on_error", "error"),
            ("on_error_container", "error_container"),
        ]:
            _appearance_ensure_contrast(result, on_role, base_role, 7.0)

    return result


def _apply_special_mode(mode: str) -> None:
    if mode not in {"oled", "dim", "high-contrast"} or not COLORS_JSON.is_file():
        return
    _write_json(COLORS_JSON, _apply_special_mode_colors(_read_json(COLORS_JSON, {}), mode))

def _snake_role(name: str) -> str:
    value = str(name).replace("-", "_")
    value = re.sub(r"(?<!^)(?=[A-Z])", "_", value).lower()
    return value


def _normalize_hex(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    match = re.fullmatch(r"#?([0-9A-Fa-f]{6})(?:[0-9A-Fa-f]{2})?", value.strip())
    if not match:
        return None
    return "#" + match.group(1).lower()


def _palette_candidate(value: Any) -> dict[str, str]:
    if not isinstance(value, dict):
        return {}
    out: dict[str, str] = {}
    role_set = set(MATERIAL_ROLES)
    for key, raw in value.items():
        role = _snake_role(str(key))
        if role not in role_set:
            continue
        color = _normalize_hex(raw)
        if color:
            out[role] = color
    return out


def _extract_matugen_palette(data: Any, mode: str) -> dict[str, str]:
    """Find the full Material role map in Matugen's version-dependent JSON."""
    candidates: list[dict[str, str]] = []

    def walk(value: Any, key_hint: str = "") -> None:
        if isinstance(value, dict):
            candidate = _palette_candidate(value)
            if candidate:
                # Prefer mode-specific objects when Matugen includes both light/dark.
                if key_hint.lower() == mode:
                    candidates.insert(0, candidate)
                else:
                    candidates.append(candidate)
            for key, child in value.items():
                walk(child, str(key))
        elif isinstance(value, list):
            for child in value:
                walk(child, key_hint)

    walk(data)
    if not candidates:
        raise RuntimeError("Matugen JSON did not contain a Material role map")
    best = max(candidates, key=lambda item: (REQUIRED_PREVIEW_ROLES.issubset(item), len(item)))
    missing = sorted(REQUIRED_PREVIEW_ROLES.difference(best))
    if missing:
        raise RuntimeError("Matugen palette is incomplete; missing " + ", ".join(missing))
    return best


def _probe_palette(seed: str, scheme: str, mode: str) -> dict[str, str]:
    py = Path(os.path.expanduser(os.environ.get(
        "NYVOREL_VIRTUAL_ENV",
        "~/.local/state/quickshell/.venv",
    ))) / "bin/python"
    if not py.is_file() or not PROBE.is_file():
        raise RuntimeError("Material palette probe is unavailable")
    proc = subprocess.run(
        [str(py), str(PROBE), "full", seed, mode, scheme],
        check=False, capture_output=True, text=True, timeout=25,
    )
    if proc.returncode != 0:
        raise RuntimeError((proc.stderr or proc.stdout or "Palette probe failed").strip()[-1200:])
    try:
        data = json.loads(proc.stdout)
    except Exception as exc:
        raise RuntimeError(f"Palette probe returned invalid JSON: {exc}") from exc
    palette = _palette_candidate(data)
    missing = sorted(REQUIRED_PREVIEW_ROLES.difference(palette))
    if missing:
        raise RuntimeError("Palette probe is incomplete; missing " + ", ".join(missing))
    return palette


def _matugen_palette(seed: str, scheme: str, mode: str) -> dict[str, str]:
    """Generate colors through Matugen without rendering any configured templates."""
    if not shutil.which("matugen"):
        raise RuntimeError("matugen is not installed")
    with tempfile.TemporaryDirectory(prefix="nyvorel-appearance-matugen-") as temp:
        config_home = Path(temp)
        config_dir = config_home / "matugen"
        config_dir.mkdir(parents=True, exist_ok=True)
        (config_dir / "config.toml").write_text("[config]\nversion_check = false\n")
        env = os.environ.copy()
        env["XDG_CONFIG_HOME"] = str(config_home)
        proc = subprocess.run(
            [
                "matugen", "color", "hex", seed,
                "--mode", mode,
                "--type", scheme,
                "--json", "hex",
            ],
            check=False, capture_output=True, text=True, timeout=25, env=env,
        )
        if proc.returncode != 0:
            raise RuntimeError((proc.stderr or proc.stdout or "Matugen palette generation failed").strip()[-1200:])
        raw = proc.stdout.strip()
        try:
            data = json.loads(raw)
        except Exception:
            first = raw.find("{")
            last = raw.rfind("}")
            if first < 0 or last <= first:
                raise RuntimeError("Matugen --json returned invalid JSON")
            try:
                data = json.loads(raw[first:last + 1])
            except Exception as exc:
                raise RuntimeError(f"Matugen --json returned invalid JSON: {exc}") from exc
        return _extract_matugen_palette(data, mode)


def _ii_generate_palette_base(seed: str, scheme: str, mode: str) -> dict[str, str]:
    errors: list[str] = []
    try:
        return _matugen_palette(seed, scheme, mode)
    except Exception as exc:
        errors.append(f"Matugen: {exc}")
    try:
        return _probe_palette(seed, scheme, mode)
    except Exception as exc:
        errors.append(f"materialyoucolor: {exc}")
    raise RuntimeError("Could not generate a Material palette. " + " | ".join(errors))

# BEGIN custom-palette-engine-v2

_II_CUSTOM_PALETTE_ANCHORS: dict[str, str] | None = None


def _ii_custom_hex(value: Any) -> str:
    if not isinstance(value, str):
        return ""
    value = value.strip()
    if re.fullmatch(r"#[0-9A-Fa-f]{6}", value):
        return value.upper()
    return ""


def _ii_parse_custom_palette_request(
    request: dict[str, Any],
    raw_seed: str,
) -> dict[str, str] | None:
    stored = request.get("customPalette")
    if isinstance(stored, dict):
        candidate = {
            "primary": _ii_custom_hex(stored.get("primary")),
            "secondary": _ii_custom_hex(stored.get("secondary")),
            "tertiary": _ii_custom_hex(stored.get("tertiary")),
            "neutral": _ii_custom_hex(stored.get("neutral")),
        }
        if all(candidate.values()):
            return candidate

    if not isinstance(raw_seed, str) or not raw_seed.startswith("ii4:"):
        return None

    parts = raw_seed[4:].split("|")
    if len(parts) != 4:
        return None

    candidate = {
        "primary": _ii_custom_hex(parts[0]),
        "secondary": _ii_custom_hex(parts[1]),
        "tertiary": _ii_custom_hex(parts[2]),
        "neutral": _ii_custom_hex(parts[3]),
    }
    return candidate if all(candidate.values()) else None


def _ii_custom_seed_transport(
    seed: str,
    custom_palette: Any,
) -> str:
    # Encode stored four-anchor Custom metadata through the existing --seed transport.
    anchors = _ii_parse_custom_palette_request(
        {"customPalette": custom_palette},
        "",
    )
    if not anchors:
        return seed
    return "ii4:" + "|".join(
        anchors[key] for key in ("primary", "secondary", "tertiary", "neutral")
    )


def _ii_copy_primary_family(
    destination: dict[str, str],
    source: dict[str, str],
    target: str,
) -> None:
    pairs = (
        ("primary", target),
        ("on_primary", f"on_{target}"),
        ("primary_container", f"{target}_container"),
        ("on_primary_container", f"on_{target}_container"),
        ("primary_fixed", f"{target}_fixed"),
        ("primary_fixed_dim", f"{target}_fixed_dim"),
        ("on_primary_fixed", f"on_{target}_fixed"),
        ("on_primary_fixed_variant", f"on_{target}_fixed_variant"),
    )
    for src, dst in pairs:
        if src in source:
            destination[dst] = source[src]


def _ii_merge_custom_palettes(primary, secondary, tertiary, neutral):
    result = deepcopy(primary)

    _ii_copy_primary_family(result, primary, "primary")
    _ii_copy_primary_family(result, secondary, "secondary")
    _ii_copy_primary_family(result, tertiary, "tertiary")

    neutral_roles = (
        "background",
        "on_background",
        "surface",
        "on_surface",
        "surface_dim",
        "surface_bright",
        "surface_container_lowest",
        "surface_container_low",
        "surface_container",
        "surface_container_high",
        "surface_container_highest",
        "surface_variant",
        "on_surface_variant",
        "outline",
        "outline_variant",
        "inverse_surface",
        "inverse_on_surface",
        "scrim",
        "shadow",
    )
    for role in neutral_roles:
        if role in neutral:
            result[role] = neutral[role]

    if "primary" in result:
        result["surface_tint"] = result["primary"]

    return result


def _generate_palette(seed: str, scheme: str, mode: str) -> dict[str, str]:
    anchors = _II_CUSTOM_PALETTE_ANCHORS
    if not anchors:
        return _ii_generate_palette_base(seed, scheme, mode)

    primary = _ii_generate_palette_base(anchors["primary"], scheme, mode)
    secondary = _ii_generate_palette_base(anchors["secondary"], scheme, mode)
    tertiary = _ii_generate_palette_base(anchors["tertiary"], scheme, mode)
    neutral = _ii_generate_palette_base(anchors["neutral"], scheme, mode)

    return _ii_merge_custom_palettes(primary, secondary, tertiary, neutral)

# END custom-palette-engine-v2



def _capture_files(paths: list[Path]) -> dict[str, bytes | None]:
    snapshot: dict[str, bytes | None] = {}
    for path in paths:
        if path.is_symlink():
            raise RuntimeError(f"Appearance transaction path is a symlink: {path}")
        if path.is_file():
            snapshot[str(path)] = path.read_bytes()
        elif path.exists():
            raise RuntimeError(f"Appearance transaction path is not a file: {path}")
        else:
            snapshot[str(path)] = None
    return snapshot


def _restore_files(snapshot: dict[str, bytes | None]) -> None:
    for raw, content in snapshot.items():
        path = Path(raw)
        if path.is_symlink():
            raise RuntimeError(f"Appearance rollback refuses symlink: {path}")
        if content is None:
            if path.exists():
                path.unlink()
            continue
        if path.is_file() and path.read_bytes() == content:
            continue
        if path.exists() and not path.is_file():
            raise RuntimeError(f"Appearance rollback target is not a file: {path}")
        path.parent.mkdir(parents=True, exist_ok=True)
        mode = (path.stat().st_mode & 0o777) if path.is_file() else 0o644
        fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.restore-", dir=str(path.parent))
        tmp = Path(tmp_name)
        try:
            with os.fdopen(fd, "wb") as output:
                output.write(content)
                output.flush()
                os.fsync(output.fileno())
            os.chmod(tmp, mode)
            os.replace(tmp, path)
        finally:
            tmp.unlink(missing_ok=True)
        if path.read_bytes() != content:
            raise RuntimeError(f"Appearance rollback verification failed: {path}")


def _gsettings_snapshot() -> dict[str, str]:
    result: dict[str, str] = {}
    for key in ("color-scheme", "gtk-theme"):
        try:
            result[key] = subprocess.run(
                ["gsettings", "get", "org.gnome.desktop.interface", key],
                check=False, capture_output=True, text=True, timeout=2,
            ).stdout.strip()
        except Exception:
            pass
    return result


def _restore_gsettings(values: dict[str, str]) -> None:
    for key, value in values.items():
        if not value:
            continue
        try:
            subprocess.run(
                ["gsettings", "set", "org.gnome.desktop.interface", key, value.strip("'\"" )],
                check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3,
            )
        except Exception:
            pass


def _all_transaction_files() -> list[Path]:
    files: list[Path] = [
        NYVOREL_CONFIG,
        STUDIO_STATE,
        COLORS_JSON,
        MATERIAL_SCSS,
        COLOR_TXT,
        WALLPAPER_TXT,
        VIDEO_RESTORE_SCRIPT,
        HYPR_CUSTOM_GENERAL,
        HYPR_CUSTOM_RULES,
        KITTY_CONFIG,
        *TERMINAL_RUNTIME_FILES,
    ]
    for paths in TARGET_FILES.values():
        files.extend(paths)
    seen: set[str] = set()
    result: list[Path] = []
    for item in files:
        key = str(item)
        if key not in seen:
            seen.add(key)
            result.append(item)
    return result

def _glass_runtime_mode_for_cfg(cfg: dict[str, Any] | None = None) -> str:
    cfg = cfg if cfg is not None else _read_json(NYVOREL_CONFIG, {})
    enabled = bool(_get_nested(cfg, "appearance.transparency.enable"))
    return "glass" if enabled else "default"


def _fluid_runtime_mode_for_cfg(cfg: dict[str, Any] | None = None) -> str:
    cfg = cfg if cfg is not None else _read_json(NYVOREL_CONFIG, {})
    return "fluid" if _detect_ui_profile(cfg) == "fluid" else "default"


def _sync_fluid_runtime_for_cfg(
    cfg: dict[str, Any] | None = None,
    *,
    best_effort: bool = False,
) -> list[str]:
    if not FLUID_RUNTIME.is_file():
        if best_effort:
            return []
        raise RuntimeError(f"Missing Fluid runtime helper: {FLUID_RUNTIME}")

    mode = _fluid_runtime_mode_for_cfg(cfg)
    command = (
        [str(FLUID_RUNTIME), mode]
        if os.access(FLUID_RUNTIME, os.X_OK)
        else [sys.executable, str(FLUID_RUNTIME), mode]
    )
    error = _run_optional_command(command, timeout=20)
    if error:
        if best_effort:
            return [f"Fluid runtime: {error}"]
        raise RuntimeError(f"Fluid runtime sync failed: {error}")
    return []


def _sync_glass_runtime_for_cfg(
    cfg: dict[str, Any] | None = None,
    *,
    best_effort: bool = False,
) -> list[str]:
    """Synchronize compositor + terminal material without touching Default at install time."""
    if not GLASS_RUNTIME.is_file():
        if best_effort:
            return []
        raise RuntimeError(f"Missing Glass runtime helper: {GLASS_RUNTIME}")
    mode = _glass_runtime_mode_for_cfg(cfg)
    command = (
        [str(GLASS_RUNTIME), mode]
        if os.access(GLASS_RUNTIME, os.X_OK)
        else [sys.executable, str(GLASS_RUNTIME), mode]
    )
    error = _run_optional_command(command, timeout=20)
    if error:
        if best_effort:
            return [f"Glass runtime: {error}"]
        raise RuntimeError(f"Glass runtime sync failed: {error}")

    # fluid-interface-v1: compose Fluid after the proven Glass substrate.
    return _sync_fluid_runtime_for_cfg(cfg, best_effort=best_effort)


def _transaction_snapshot() -> dict[str, Any]:
    return {
        "files": _capture_files(_all_transaction_files()),
        "gsettings": _gsettings_snapshot(),
    }


def _restore_transaction(snapshot: dict[str, Any]) -> None:
    files = snapshot.get("files", {})
    _restore_files(files)
    _restore_gsettings(snapshot.get("gsettings", {}))
    _sync_glass_runtime_for_cfg(_read_json(NYVOREL_CONFIG, {}), best_effort=True)
    # Runtime helpers can normalize managed files while resynchronizing. The
    # transaction owns the exact original bytes, including personal edits.
    rules_after_sync = HYPR_CUSTOM_RULES.read_bytes() if HYPR_CUSTOM_RULES.is_file() else None
    _restore_files(files)
    if rules_after_sync != (HYPR_CUSTOM_RULES.read_bytes() if HYPR_CUSTOM_RULES.is_file() else None):
        _run_optional_command(["hyprctl", "reload"], timeout=8)


def _apply_ui_snapshot(snapshot: dict[str, Any] | None) -> None:
    if not snapshot:
        return
    allowed = set(_config_snapshot().keys())
    cfg = _read_json(NYVOREL_CONFIG, {})
    for key, value in snapshot.items():
        if key in allowed and value is not None:
            _set_nested(cfg, key, value)
    _write_json(NYVOREL_CONFIG, cfg)


def _files_for_disabled_targets(targets: dict[str, bool]) -> list[Path]:
    paths: list[Path] = []
    for target, target_paths in TARGET_FILES.items():
        if not bool(targets.get(target, True)):
            paths.extend(target_paths)
    return paths

def _update_engine_flags(cfg: dict[str, Any], targets: dict[str, bool]) -> None:
    theming = cfg.setdefault("appearance", {}).setdefault("wallpaperTheming", {})
    # Core Matugen generation stays enabled so independently enabled targets can
    # update. Disabled outputs are restored from the transaction snapshot.
    theming["enableAppsAndShell"] = True
    theming["enableQtApps"] = bool(targets.get("qt", True))
    theming["enableTerminal"] = bool(targets.get("terminal", True))


def _apply_target_flags_to_cfg(cfg: dict[str, Any], targets: dict[str, bool]) -> None:
    theming = cfg.setdefault("appearance", {}).setdefault("wallpaperTheming", {})
    theming["enableQtApps"] = bool(targets.get("qt", True))
    theming["enableTerminal"] = bool(targets.get("terminal", True))

def _run_switchwall(mode: str, scheme: str, seed: str, *, targets: dict[str, bool]) -> None:
    if not SWITCHWALL.is_file():
        raise RuntimeError(f"Missing switchwall.sh: {SWITCHWALL}")
    cmd = [str(SWITCHWALL), "--noswitch", "--mode", mode, "--type", scheme, "--color", seed]
    env = os.environ.copy()
    env["NYVOREL_APPEARANCE_STUDIO_MANAGED"] = "1"
    env["NYVOREL_APPEARANCE_STUDIO_SKIP_TERMINAL"] = "1"
    env["NYVOREL_APPEARANCE_STUDIO_SKIP_GSETTINGS"] = "0" if targets.get("gtk", True) else "1"
    proc = subprocess.run(cmd, check=False, capture_output=True, text=True, timeout=90, env=env)
    if proc.returncode != 0:
        details = (proc.stderr or proc.stdout).strip()
        raise RuntimeError(f"Theme generation failed ({proc.returncode}): {details[-1400:]}")

def _preset_by_id(preset_id: str) -> dict[str, Any]:
    for preset in PRESETS:
        if preset["id"] == preset_id:
            return preset
    raise RuntimeError(f"Unknown preset: {preset_id}")


def _ii_make_active_base(source: str, mode: str, scheme: str, wallpaper: str, preset: str, seed: str, ui_profile: str) -> dict[str, Any]:
    return {
        "source": source,
        "mode": mode,
        "scheme": scheme,
        "wallpaper": wallpaper,
        "preset": preset,
        "seed": seed,
        "uiProfile": ui_profile,
    }

def _make_active(
    source,
    mode,
    scheme,
    wallpaper,
    preset,
    seed,
    ui_profile,
):
    active = _ii_make_active_base(
        source,
        mode,
        scheme,
        wallpaper,
        preset,
        seed,
        ui_profile,
    )
    if source == "custom" and _II_CUSTOM_PALETTE_ANCHORS:
        active["customPalette"] = deepcopy(_II_CUSTOM_PALETTE_ANCHORS)
    return active



def _runtime_committed_view(state: dict[str, Any], cfg: dict[str, Any] | None = None) -> tuple[dict[str, Any], dict[str, Any]]:
    """Reconcile Studio metadata with II changes made outside the Studio."""
    cfg = cfg or _read_json(NYVOREL_CONFIG, {})
    active = deepcopy(state.get("active", {}))
    ui = _config_snapshot()
    if state.get("preview"):
        return active, deepcopy(state.get("activeUi") or ui)

    wallpaper = str(cfg.get("background", {}).get("wallpaperPath", "") or "")
    palette = cfg.get("appearance", {}).get("palette", {})
    accent = str(palette.get("accentColor", "") or "")
    scheme = str(palette.get("type", "") or "")
    old_wallpaper = str(active.get("wallpaper", "") or "")

    if wallpaper:
        active["wallpaper"] = wallpaper
    if scheme:
        active["scheme"] = scheme
    active["uiProfile"] = _detect_ui_profile(cfg)

    # If the wallpaper changed through II's native switcher and no fixed accent
    # is configured, the resulting palette is wallpaper-derived. Do not leave a
    # stale preset/custom source in Studio metadata.
    if wallpaper and wallpaper != old_wallpaper and not accent:
        active["source"] = "wallpaper"
        active["preset"] = ""
        active["seed"] = ""
    elif accent and active.get("source") in {"preset", "custom"}:
        active["seed"] = accent.lower()

    return active, ui


def _reconcile_state_before_mutation(state: dict[str, Any]) -> dict[str, Any]:
    if state.get("preview"):
        return state
    active, ui = _runtime_committed_view(state)
    if active != state.get("active") or ui != state.get("activeUi"):
        state = deepcopy(state)
        state["active"] = active
        state["activeUi"] = ui
        _save_state(state)
    return state


def _appearance_fingerprint(active: dict[str, Any], ui: dict[str, Any]) -> str:
    payload = json.dumps(
        {"active": active, "ui": ui},
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    )
    return hashlib.sha256(payload.encode()).hexdigest()[:20]


def _history_entry(active: dict[str, Any], ui: dict[str, Any], colors: dict[str, Any] | None = None) -> dict[str, Any]:
    scheme_name = next((name for value, name in SCHEMES if value == active.get("scheme")), active.get("scheme", "Theme"))
    source = active.get("source", "wallpaper")
    if source == "preset":
        try:
            source_name = _preset_by_id(active.get("preset", ""))["name"]
        except Exception:
            source_name = "Preset"
    elif source == "hybrid":
        try:
            base_name = _preset_by_id(active.get("preset", ""))["name"]
        except Exception:
            base_name = "Preset"
        wall_name = Path(active.get("wallpaper", "")).stem or "Wallpaper"
        source_name = f"{wall_name} + {base_name}"
    elif source == "custom":
        source_name = active.get("seed", "Custom")
    else:
        source_name = Path(active.get("wallpaper", "")).stem or "Wallpaper"

    ui = deepcopy(ui)
    return {
        "id": uuid.uuid4().hex[:12],
        "timestamp": int(time.time()),
        "label": f"{source_name} · {scheme_name} · {str(active.get('mode', 'dark')).title()}",
        "customLabel": False,
        "fingerprint": _appearance_fingerprint(active, ui),
        "active": deepcopy(active),
        "colors": deepcopy(colors if colors is not None else _read_json(COLORS_JSON, {})),
        "ui": ui,
    }

def _prepare_preview_snapshot(state: dict[str, Any]) -> None:
    # One immutable baseline per preview session.
    if PREVIEW_DIR.is_dir() and (PREVIEW_DIR / "manifest.json").is_file() and (PREVIEW_DIR / "state-before.json").is_file():
        return

    shutil.rmtree(PREVIEW_DIR, ignore_errors=True)
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)

    files = []
    for paths in TARGET_FILES.values():
        files.extend(paths)
    files += [
        NYVOREL_CONFIG,
        GENERATED / "material_colors.scss",
        GENERATED / "color.txt",
        HYPR_CUSTOM_RULES,
        KITTY_CONFIG,
        *TERMINAL_RUNTIME_FILES,
    ]

    manifest: dict[str, str | None] = {}
    store = PREVIEW_DIR / "files"
    store.mkdir(parents=True, exist_ok=True)
    for i, item in enumerate(files):
        key = f"{i:03d}"
        if item.is_file():
            target = store / key
            target.write_bytes(item.read_bytes())
            manifest[str(item)] = key
        else:
            manifest[str(item)] = None
    _write_json(PREVIEW_DIR / "manifest.json", manifest)
    _write_json(PREVIEW_DIR / "gsettings.json", _gsettings_snapshot())
    baseline = deepcopy(state)
    baseline["preview"] = None
    _write_json(PREVIEW_DIR / "state-before.json", baseline)


def _restore_preview_runtime(*, remove: bool) -> None:
    preview_cfg = _read_json(NYVOREL_CONFIG, {})
    manifest = _read_json(PREVIEW_DIR / "manifest.json", {})
    store = PREVIEW_DIR / "files"
    snapshot: dict[str, bytes | None] = {}
    for raw_path, key in manifest.items():
        saved = store / key if key is not None else None
        if saved is not None and not saved.is_file():
            raise RuntimeError(f"Missing preview backup for {raw_path}")
        snapshot[raw_path] = saved.read_bytes() if saved is not None else None
    _restore_files(snapshot)
    _restore_gsettings(_read_json(PREVIEW_DIR / "gsettings.json", {}))
    restored_cfg = _read_json(NYVOREL_CONFIG, {})
    runtime_changed = (
        _glass_runtime_mode_for_cfg(preview_cfg), _fluid_runtime_mode_for_cfg(preview_cfg)
    ) != (
        _glass_runtime_mode_for_cfg(restored_cfg), _fluid_runtime_mode_for_cfg(restored_cfg)
    )
    if runtime_changed:
        _sync_glass_runtime_for_cfg(restored_cfg, best_effort=True)
        # Glass/Fluid synchronization may reformat the just-restored rules and
        # terminal files. Finish with the immutable preview bytes.
        rules_after_sync = HYPR_CUSTOM_RULES.read_bytes() if HYPR_CUSTOM_RULES.is_file() else None
        _restore_files(snapshot)
        if rules_after_sync != (HYPR_CUSTOM_RULES.read_bytes() if HYPR_CUSTOM_RULES.is_file() else None):
            _run_optional_command(["hyprctl", "reload"], timeout=8)
    if remove:
        shutil.rmtree(PREVIEW_DIR, ignore_errors=True)


def _baseline_state_preserving_globals(current: dict[str, Any]) -> dict[str, Any]:
    baseline = _read_json(PREVIEW_DIR / "state-before.json", _default_state())
    for key in ("targets", "favorites", "history"):
        if key in current:
            baseline[key] = deepcopy(current[key])
    baseline["version"] = STATE_VERSION
    baseline["preview"] = None
    return baseline


def _merge_hybrid_surfaces(base_colors: dict[str, Any], accent_colors: dict[str, Any]) -> dict[str, Any]:
    merged = deepcopy(accent_colors)
    for role in HYBRID_SURFACE_ROLES:
        if role in base_colors:
            merged[role] = base_colors[role]
    return merged


def _stop_mpvpaper() -> None:
    if shutil.which("pkill"):
        subprocess.run(
            ["pkill", "-f", "mpvpaper"],
            check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )


def _hyprland_monitors() -> list[str]:
    if not shutil.which("hyprctl"):
        return []
    proc = subprocess.run(
        ["hyprctl", "monitors", "-j"],
        check=False, capture_output=True, text=True, timeout=5,
    )
    if proc.returncode != 0:
        return []
    try:
        data = json.loads(proc.stdout)
    except Exception:
        return []
    return [str(item.get("name")) for item in data if item.get("name")]


def _write_video_restore_script(video: str) -> None:
    VIDEO_RESTORE_SCRIPT.parent.mkdir(parents=True, exist_ok=True)
    video_q = shlex.quote(str(_local_path(video)))
    opts_q = shlex.quote(VIDEO_OPTS)
    content = (
        "#!/usr/bin/env bash\n"
        "# Generated by Appearance Studio.\n"
        "pkill -f mpvpaper 2>/dev/null || true\n"
        "for monitor in $(hyprctl monitors -j | jq -r '.[] | .name'); do\n"
        f"    mpvpaper -o {opts_q} \"$monitor\" {video_q} >/dev/null 2>&1 &\n"
        "    sleep 0.1\n"
        "done\n"
    )
    VIDEO_RESTORE_SCRIPT.write_text(content)
    VIDEO_RESTORE_SCRIPT.chmod(0o755)


def _clear_video_restore_script() -> None:
    VIDEO_RESTORE_SCRIPT.parent.mkdir(parents=True, exist_ok=True)
    VIDEO_RESTORE_SCRIPT.write_text(
        "#!/usr/bin/env bash\n# No video wallpaper currently needs restoring.\n"
    )
    VIDEO_RESTORE_SCRIPT.chmod(0o755)


def _apply_wallpaper_runtime(wallpaper: str, cfg: dict[str, Any], *, best_effort: bool = False) -> None:
    """Apply only runtime pieces that Config cannot represent by itself."""
    try:
        if not wallpaper:
            return
        path = str(_local_path(wallpaper))
        if not _is_video(path):
            _stop_mpvpaper()
            _clear_video_restore_script()
            return

        if not shutil.which("mpvpaper"):
            raise RuntimeError("mpvpaper is required for video wallpapers")
        if not shutil.which("ffmpeg"):
            raise RuntimeError("ffmpeg is required for video wallpapers")
        if not _local_path(path).is_file():
            raise RuntimeError(f"Video wallpaper not found: {path}")

        monitors = _hyprland_monitors()
        if not monitors:
            raise RuntimeError("Could not determine Hyprland monitors for video wallpaper")

        _stop_mpvpaper()
        for monitor in monitors:
            subprocess.Popen(
                ["mpvpaper", "-o", VIDEO_OPTS, monitor, path],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
                close_fds=True,
            )
            time.sleep(0.08)
        _write_video_restore_script(path)
    except Exception:
        if best_effort:
            return
        raise


def _run_optional_command(command: list[str], *, env: dict[str, str] | None = None, timeout: int = 30) -> str | None:
    try:
        proc = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
        )
        if proc.returncode != 0:
            detail = (proc.stderr or proc.stdout or "unknown failure").strip()[-800:]
            return detail or f"exit code {proc.returncode}"
    except Exception as exc:
        return str(exc)
    return None


def _run_post_commit_integrations(
    targets: dict[str, bool],
    *,
    resolved_scheme: str,
) -> list[str]:
    """Best-effort integrations. Core appearance is already committed."""
    warnings: list[str] = []

    if targets.get("terminal", True) and APPLYCOLOR.is_file():
        env = os.environ.copy()
        env["NYVOREL_APPEARANCE_STUDIO_MANAGED"] = "1"
        env["NYVOREL_APPEARANCE_STUDIO_SKIP_TERMINAL"] = "0"
        error = _run_optional_command([str(APPLYCOLOR)], env=env, timeout=20)
        if error:
            warnings.append(f"Terminal theme: {error}")

    if targets.get("editors", True) and EDITOR_COLOR_SCRIPT.is_file():
        editor_before = _capture_files(EDITOR_SETTINGS)
        command = [str(EDITOR_COLOR_SCRIPT)] if os.access(EDITOR_COLOR_SCRIPT, os.X_OK) else ["bash", str(EDITOR_COLOR_SCRIPT)]
        error = _run_optional_command(command, timeout=30)
        if error:
            _restore_files(editor_before)
            warnings.append(f"Editor accents: {error}")

    if targets.get("qt", True) and QT_WRAPPER.is_file():
        command = [str(QT_WRAPPER), "--scheme-variant", resolved_scheme]
        if not os.access(QT_WRAPPER, os.X_OK):
            command = ["bash", str(QT_WRAPPER), "--scheme-variant", resolved_scheme]
        error = _run_optional_command(command, timeout=30)
        if error:
            warnings.append(f"Qt/KDE theme: {error}")

    return warnings

def _launch_preview_watchdog(token: str, revision: int) -> None:
    try:
        subprocess.Popen(
            [
                sys.executable,
                str(Path(__file__).resolve()),
                "preview-watchdog",
                "--token", token,
                "--revision", str(revision),
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
            close_fds=True,
        )
    except Exception:
        pass


def preview_watchdog(token: str, revision: int) -> dict[str, Any]:
    # Backend-only expiry authority. Older watchdogs become harmless as soon as
    # a newer preview revision is committed.
    while True:
        state = _load_state()
        preview = state.get("preview") or {}
        if preview.get("token") != token or int(preview.get("revision", -1)) != revision:
            return {"ok": True, "expired": False}

        remaining = float(preview.get("expiresAt", 0)) - time.time()
        if remaining > 0:
            time.sleep(min(remaining + 0.05, 5.0))
            continue

        with _mutation_lock():
            state = _load_state()
            preview = state.get("preview") or {}
            if (
                preview.get("token") == token
                and int(preview.get("revision", -1)) == revision
                and time.time() >= float(preview.get("expiresAt", 0))
            ):
                return revert_preview()
        return {"ok": True, "expired": False}



# BEGIN appearance-intelligence-v1
SMART_PALETTE_VERSION = "1"
SMART_SEED_LIMIT = max(
    1,
    min(5, int(os.environ.get("NYVOREL_APPEARANCE_SMART_SEEDS", "3"))),
)
SMART_CACHE_DIR = XDG_CACHE / "nyvorel-appearance-studio/intelligence"


def _smart_clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    return max(low, min(high, value))


def _smart_rgb(value: str) -> tuple[float, float, float]:
    if not isinstance(value, str) or not re.fullmatch(r"#[0-9A-Fa-f]{6}", value):
        raise ValueError(f"Invalid color: {value!r}")
    return tuple(int(value[i:i + 2], 16) / 255.0 for i in (1, 3, 5))


def _smart_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _smart_oklab(value: str) -> tuple[float, float, float]:
    r, g, b = (_smart_linear(c) for c in _smart_rgb(value))
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


def _smart_distance(a: str, b: str) -> float:
    x = _smart_oklab(a)
    y = _smart_oklab(b)
    return math.sqrt(sum((u - v) ** 2 for u, v in zip(x, y)))


def _smart_ab_distance(a: str, b: str) -> float:
    x = _smart_oklab(a)
    y = _smart_oklab(b)
    return math.hypot(x[1] - y[1], x[2] - y[2])


def _smart_chroma(value: str) -> float:
    _, a, b = _smart_oklab(value)
    return math.hypot(a, b)


def _smart_relative_luminance(value: str) -> float:
    r, g, b = (_smart_linear(c) for c in _smart_rgb(value))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def _smart_contrast(a: str, b: str) -> float:
    l1 = _smart_relative_luminance(a)
    l2 = _smart_relative_luminance(b)
    return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)


def _wallpaper_profile(path: str) -> dict[str, Any]:
    p = _local_path(path)
    if not p.is_file():
        raise RuntimeError(f"Wallpaper not found: {p}")

    if WALLPAPER_PROFILE.is_file():
        proc = subprocess.run(
            ["python3", str(WALLPAPER_PROFILE), str(p)],
            check=False,
            capture_output=True,
            text=True,
            timeout=25,
        )
        if proc.returncode == 0:
            try:
                data = json.loads(proc.stdout)
                if data.get("ok") and data.get("accentCandidates"):
                    return data
            except Exception:
                pass

    seed = _source_color_from_image(str(p))
    return {
        "ok": True,
        "image": str(p),
        "environment": seed,
        "meanLuminance": _smart_relative_luminance(seed),
        "darkFraction": 0.0,
        "brightFraction": 0.0,
        "colorfulness": _smart_clamp(_smart_chroma(seed) / 0.16),
        "colors": [{"hex": seed, "population": 1.0}],
        "accentCandidates": [{"hex": seed, "score": 1.0, "population": 1.0}],
        "fallback": True,
    }


def _matugen_image_candidates(path: str) -> list[str]:
    p = _local_path(path)
    if not p.is_file() or not shutil.which("matugen"):
        return []
    try:
        proc = subprocess.run(
            ["matugen", "image-colors", str(p)],
            check=False,
            capture_output=True,
            text=True,
            timeout=15,
        )
    except Exception:
        return []
    return [
        value.lower()
        for value in re.findall(
            r"#[0-9A-Fa-f]{6}",
            proc.stdout + "\n" + proc.stderr,
        )
    ]


def _smart_seed_candidates(path: str, profile: dict[str, Any]) -> list[str]:
    profile_colors = [
        str(item.get("hex", "")).lower()
        for item in profile.get("accentCandidates", [])
        if re.fullmatch(r"#[0-9A-Fa-f]{6}", str(item.get("hex", "")))
    ]
    matugen_colors = _matugen_image_candidates(path)

    ordered = []
    for i in range(max(len(profile_colors), len(matugen_colors))):
        if i < len(profile_colors):
            ordered.append(profile_colors[i])
        if i < len(matugen_colors):
            ordered.append(matugen_colors[i])

    if not ordered:
        ordered.append(_source_color_from_image(path))

    selected = []
    for value in ordered:
        if value in selected:
            continue
        try:
            distinct = all(_smart_distance(value, old) >= 0.045 for old in selected)
        except Exception:
            distinct = True
        if distinct:
            selected.append(value)
        if len(selected) >= SMART_SEED_LIMIT:
            break

    return selected or [_source_color_from_image(path)]


def _smart_role(palette: dict[str, Any], *names: str) -> str:
    for name in names:
        value = palette.get(name)
        if isinstance(value, str) and re.fullmatch(r"#[0-9A-Fa-f]{6}", value):
            return value.lower()
    return ""


def _score_real_palette(
    profile: dict[str, Any],
    palette: dict[str, Any],
    seed: str,
) -> tuple[float, dict[str, float]]:
    primary = _smart_role(palette, "primary")
    secondary = _smart_role(palette, "secondary")
    tertiary = _smart_role(palette, "tertiary")
    surface = _smart_role(palette, "surface_container", "surface", "background")
    on_surface = _smart_role(palette, "on_surface", "on_background")

    if not primary or not surface or not on_surface:
        raise RuntimeError("Generated palette lacks roles required for scoring")

    wallpaper_accents = [
        str(item.get("hex", "")).lower()
        for item in profile.get("accentCandidates", [])
        if re.fullmatch(r"#[0-9A-Fa-f]{6}", str(item.get("hex", "")))
    ] or [seed]

    environment = str(profile.get("environment") or seed).lower()
    if not re.fullmatch(r"#[0-9A-Fa-f]{6}", environment):
        environment = seed

    harmony_distance = min(
        _smart_distance(primary, candidate)
        for candidate in wallpaper_accents
    )
    wallpaper_harmony = 1.0 - _smart_clamp(harmony_distance / 0.30)

    surface_harmony = 1.0 - _smart_clamp(
        _smart_ab_distance(surface, environment) / 0.15
    )

    semantic_pairs = [(on_surface, surface)]
    for on_name, base in (
        ("on_primary", primary),
        ("on_secondary", secondary),
        ("on_tertiary", tertiary),
    ):
        on_value = _smart_role(palette, on_name)
        if on_value and base:
            semantic_pairs.append((on_value, base))

    readability_values = [
        _smart_clamp((_smart_contrast(fg, bg) - 3.0) / 4.0)
        for fg, bg in semantic_pairs
    ]
    readability = sum(readability_values) / len(readability_values)

    accent_contrast = _smart_clamp(
        (_smart_contrast(primary, surface) - 1.25) / 3.75
    )
    accent_separation = _smart_clamp(
        _smart_distance(primary, surface) / 0.32
    )

    accents = [value for value in (primary, secondary, tertiary) if value]
    if len(accents) >= 2:
        pair_distances = []
        for i in range(len(accents)):
            for j in range(i + 1, len(accents)):
                pair_distances.append(
                    _smart_clamp(
                        _smart_distance(accents[i], accents[j]) / 0.18
                    )
                )
        diversity = sum(pair_distances) / len(pair_distances)
    else:
        diversity = 0.5

    surface_comfort = 1.0 - _smart_clamp(_smart_chroma(surface) / 0.13)

    wallpaper_colorfulness = _smart_clamp(
        float(profile.get("colorfulness", 0.5))
    )
    palette_chroma = (
        sum(_smart_chroma(value) for value in accents)
        / max(1, len(accents))
    )
    target_chroma = 0.045 + 0.125 * wallpaper_colorfulness
    chroma_match = 1.0 - _smart_clamp(
        abs(palette_chroma - target_chroma) / 0.15
    )

    seed_affinity = 1.0 - _smart_clamp(
        _smart_distance(primary, seed) / 0.30
    )

    metrics = {
        "wallpaperHarmony": wallpaper_harmony,
        "surfaceHarmony": surface_harmony,
        "readability": readability,
        "accentContrast": accent_contrast,
        "accentSeparation": accent_separation,
        "diversity": diversity,
        "surfaceComfort": surface_comfort,
        "chromaMatch": chroma_match,
        "seedAffinity": seed_affinity,
    }

    score = (
        0.23 * wallpaper_harmony
        + 0.12 * surface_harmony
        + 0.20 * readability
        + 0.10 * accent_contrast
        + 0.11 * accent_separation
        + 0.06 * diversity
        + 0.08 * surface_comfort
        + 0.06 * chroma_match
        + 0.04 * seed_affinity
    )

    return score, metrics


def _smart_reason(metrics: dict[str, float]) -> str:
    labels = {
        "wallpaperHarmony": "wallpaper harmony",
        "surfaceHarmony": "surface harmony",
        "readability": "readability",
        "accentContrast": "accent contrast",
        "accentSeparation": "accent separation",
        "diversity": "color diversity",
        "surfaceComfort": "surface comfort",
        "chromaMatch": "balanced chroma",
    }
    ranked = sorted(
        (
            (float(value), labels[key])
            for key, value in metrics.items()
            if key in labels
        ),
        reverse=True,
    )
    return " · ".join(label for _, label in ranked[:3])


def _smart_cache_path(
    path: str,
    base_mode: str,
    display_mode: str,
) -> Path:
    p = _local_path(path)
    stat = p.stat()
    profile_mtime = (
        WALLPAPER_PROFILE.stat().st_mtime_ns
        if WALLPAPER_PROFILE.is_file()
        else 0
    )
    payload = "|".join(
        [
            SMART_PALETTE_VERSION,
            str(p.resolve()),
            str(stat.st_size),
            str(stat.st_mtime_ns),
            str(profile_mtime),
            base_mode,
            display_mode,
            str(SMART_SEED_LIMIT),
        ]
    )
    digest = hashlib.sha256(payload.encode()).hexdigest()
    SMART_CACHE_DIR.mkdir(parents=True, exist_ok=True)
    return SMART_CACHE_DIR / f"{digest}.json"


def _smart_wallpaper_matrix(
    path: str,
    base_mode: str,
    display_mode: str,
) -> dict[str, Any]:
    cache = _smart_cache_path(path, base_mode, display_mode)

    try:
        cached = _read_json(cache, {})
        if (
            cached.get("version") == SMART_PALETTE_VERSION
            and cached.get("evaluations")
            and cached.get("best")
        ):
            return cached
    except Exception:
        pass

    profile = _wallpaper_profile(path)
    seeds = _smart_seed_candidates(path, profile)
    schemes = [value for value, _ in SCHEMES if value != "auto"]

    evaluations = []
    errors = []

    for seed in seeds:
        for scheme in schemes:
            try:
                palette = _generate_palette(seed, scheme, base_mode)
                visible = _apply_special_mode_colors(palette, display_mode)
                score, metrics = _score_real_palette(profile, visible, seed)
                evaluations.append(
                    {
                        "seed": seed.lower(),
                        "scheme": scheme,
                        "score": score,
                        "metrics": metrics,
                        "reason": _smart_reason(metrics),
                        "palette": palette,
                        "visiblePalette": visible,
                    }
                )
            except Exception as exc:
                errors.append(f"{seed}/{scheme}: {exc}")

    if not evaluations:
        raise RuntimeError(
            "Appearance intelligence could not generate any candidate palette. "
            + " | ".join(errors[:3])
        )

    evaluations.sort(key=lambda item: item["score"], reverse=True)
    best = deepcopy(evaluations[0])

    result = {
        "version": SMART_PALETTE_VERSION,
        "image": str(_local_path(path)),
        "baseMode": base_mode,
        "displayMode": display_mode,
        "profile": profile,
        "seeds": seeds,
        "best": {
            key: deepcopy(value)
            for key, value in best.items()
            if key not in {"palette", "visiblePalette"}
        },
        "evaluations": evaluations,
        "errors": errors[:8],
    }

    try:
        _write_json(cache, result)
    except Exception:
        pass

    return result


def _smart_wallpaper_choice(
    path: str,
    base_mode: str,
    requested_scheme: str,
    display_mode: str,
) -> dict[str, Any]:
    try:
        matrix = _smart_wallpaper_matrix(path, base_mode, display_mode)

        if requested_scheme == "auto":
            chosen = matrix["best"]
        else:
            options = [
                item
                for item in matrix["evaluations"]
                if item.get("scheme") == requested_scheme
            ]
            if not options:
                raise RuntimeError(
                    f"No smart palette candidate for {requested_scheme}"
                )
            chosen = max(options, key=lambda item: item["score"])

        return {
            "seed": chosen["seed"],
            "scheme": chosen["scheme"],
            "score": chosen.get("score"),
            "metrics": deepcopy(chosen.get("metrics", {})),
            "reason": chosen.get("reason", ""),
            "profile": deepcopy(matrix.get("profile", {})),
            "candidateSeeds": deepcopy(matrix.get("seeds", [])),
            "engine": "semantic-palette-score-v1",
        }
    except Exception as exc:
        seed = _source_color_from_image(path)
        scheme = _resolve_scheme(requested_scheme, path)
        return {
            "seed": seed,
            "scheme": scheme,
            "score": None,
            "metrics": {},
            "reason": "legacy fallback",
            "profile": {},
            "candidateSeeds": [seed],
            "engine": "legacy-fallback",
            "warning": str(exc),
        }


# END appearance-intelligence-v1


def _theme_request(
    *,
    source: str,
    mode: str,
    scheme: str,
    preset: str,
    seed: str,
    wallpaper: str,
    ui_snapshot: dict[str, Any] | None,
) -> dict[str, Any]:
    return {
        "source": source,
        "mode": mode,
        "scheme": scheme,
        "preset": preset,
        "seed": seed,
        "wallpaper": wallpaper,
        "ui": deepcopy(ui_snapshot or {}),
    }


def _resolve_request(request: dict[str, Any], cfg: dict[str, Any], *, preview: bool) -> dict[str, Any]:
    source = str(request.get("source") or "wallpaper")
    requested_mode = str(request.get("mode") or "dark")
    requested_scheme = str(request.get("scheme") or "auto")
    preset = str(request.get("preset") or "")
    raw_seed = str(request.get("seed") or "")
    global _II_CUSTOM_PALETTE_ANCHORS
    _II_CUSTOM_PALETTE_ANCHORS = _ii_parse_custom_palette_request(request, raw_seed)
    if _II_CUSTOM_PALETTE_ANCHORS:
        raw_seed = _II_CUSTOM_PALETTE_ANCHORS["primary"]
        request["seed"] = raw_seed
        request["customPalette"] = deepcopy(_II_CUSTOM_PALETTE_ANCHORS)
    wallpaper = str(request.get("wallpaper") or "")
    if wallpaper:
        wallpaper = str(_local_path(wallpaper))
    else:
        wallpaper = _current_wallpaper(cfg)

    ui = deepcopy(request.get("ui") or {})
    source_image = ""
    hybrid_base: dict[str, Any] = {}
    intelligence: dict[str, Any] | None = None

    if source == "preset":
        selected = _preset_by_id(preset or "midnight")
        preset = selected["id"]
        seed = selected["seed"]
        resolved_scheme = selected["scheme"] if requested_scheme == "auto" else requested_scheme
    elif source == "custom":
        if not re.fullmatch(r"#?[0-9A-Fa-f]{6}", raw_seed):
            raise RuntimeError("Custom color must be a 6-digit hex color")
        seed = raw_seed if raw_seed.startswith("#") else "#" + raw_seed
        resolved_scheme = "scheme-tonal-spot" if requested_scheme == "auto" else requested_scheme
    elif source == "hybrid":
        if not wallpaper:
            raise RuntimeError("No wallpaper is configured")
        source_image = _source_image_for_wallpaper(wallpaper, cfg, preview=preview)
        base_mode = _resolve_base_mode(requested_mode, source_image)
        intelligence = _smart_wallpaper_choice(
            source_image,
            base_mode,
            requested_scheme,
            requested_mode,
        )
        seed = intelligence["seed"]
        resolved_scheme = intelligence["scheme"]
        hybrid_base = _preset_by_id(preset or "midnight")
        preset = hybrid_base["id"]
    else:
        source = "wallpaper"
        if not wallpaper:
            raise RuntimeError("No wallpaper is configured")
        source_image = _source_image_for_wallpaper(wallpaper, cfg, preview=preview)
        base_mode = _resolve_base_mode(requested_mode, source_image)
        intelligence = _smart_wallpaper_choice(
            source_image,
            base_mode,
            requested_scheme,
            requested_mode,
        )
        seed = intelligence["seed"]
        resolved_scheme = intelligence["scheme"]

    allowed = {value for value, _ in SCHEMES if value != "auto"}
    if resolved_scheme not in allowed:
        raise RuntimeError(f"Unsupported Material scheme: {resolved_scheme}")

    base_mode = _resolve_base_mode(requested_mode, source_image or wallpaper)
    return {
        "source": source,
        "mode": requested_mode,
        "baseMode": base_mode,
        "scheme": requested_scheme,
        "resolvedScheme": resolved_scheme,
        "preset": preset,
        "seed": seed.lower(),
        "wallpaper": wallpaper,
        "sourceImage": source_image,
        "ui": ui,
        "hybridBase": deepcopy(hybrid_base),
        "intelligence": deepcopy(intelligence),
    }

def _render_preview(request: dict[str, Any]) -> dict[str, Any]:
    # Preview keeps palette generation shell-local. Interface-material runtime
    # (Glass compositor rules + Kitty opacity) follows the candidate and is
    # restored atomically when the preview is reverted or times out.
    state = _load_state()
    targets = deepcopy(state.get("targets", {}))
    cfg = _read_json(NYVOREL_CONFIG, {})
    runtime_before = (_glass_runtime_mode_for_cfg(cfg), _fluid_runtime_mode_for_cfg(cfg))
    resolved = _resolve_request(request, cfg, preview=True)

    _apply_ui_snapshot_to_cfg(cfg, resolved.get("ui"))
    _apply_target_flags_to_cfg(cfg, targets)

    wallpaper = resolved["wallpaper"]
    if wallpaper:
        # Video previews are represented by a static extracted frame. Keep or
        # Apply starts mpvpaper only after the full transaction commits.
        display_path = resolved["sourceImage"] if _is_video(wallpaper) else wallpaper
        cfg.setdefault("background", {})["wallpaperPath"] = display_path
        if _is_video(wallpaper):
            cfg["background"]["thumbnailPath"] = resolved["sourceImage"]

    if targets.get("shell", True):
        cfg.setdefault("appearance", {}).setdefault("palette", {})["type"] = resolved["scheme"]
        cfg["appearance"]["palette"]["accentColor"] = (
            resolved["seed"] if resolved["source"] in {"preset", "custom"} else ""
        )
        if resolved["source"] == "hybrid":
            base = resolved["hybridBase"]
            base_colors = _generate_palette(base["seed"], base["scheme"], resolved["baseMode"])
            accent_colors = _generate_palette(resolved["seed"], resolved["resolvedScheme"], resolved["baseMode"])
            colors = _merge_hybrid_surfaces(base_colors, accent_colors)
        else:
            colors = _generate_palette(resolved["seed"], resolved["resolvedScheme"], resolved["baseMode"])
        colors = _apply_special_mode_colors(colors, resolved["mode"])
        _write_json(COLORS_JSON, colors)

    _ensure_radius_geometry(cfg)
    _write_json(NYVOREL_CONFIG, cfg)
    if runtime_before != (_glass_runtime_mode_for_cfg(cfg), _fluid_runtime_mode_for_cfg(cfg)):
        _sync_glass_runtime_for_cfg(cfg)
    candidate = _make_active(
        resolved["source"],
        resolved["mode"],
        resolved["scheme"],
        resolved["wallpaper"],
        resolved["preset"],
        resolved["seed"],
        _detect_ui_profile(cfg),
    )
    return {"active": candidate, "resolved": resolved}


def _apply_theme_core(
    *,
    source: str,
    mode: str,
    scheme: str,
    preset: str = "",
    seed: str = "",
    wallpaper: str = "",
    preview: bool = False,
    record_history: bool = True,
    ui_snapshot: dict[str, Any] | None = None,
) -> dict[str, Any]:
    request = _theme_request(
        source=source,
        mode=mode,
        scheme=scheme,
        preset=preset,
        seed=seed,
        wallpaper=wallpaper,
        ui_snapshot=ui_snapshot,
    )
    if preview:
        rendered = _render_preview(request)
        return {
            "ok": True,
            "active": rendered["active"],
            "preview": True,
            "previewTimeout": PREVIEW_TIMEOUT_SECONDS,
            "resolvedScheme": rendered["resolved"]["resolvedScheme"],
        }

    state = _load_state()
    targets = deepcopy(state.get("targets", {}))
    cfg_before = _read_json(NYVOREL_CONFIG, {})
    previous_wallpaper = _current_wallpaper(cfg_before)
    previous_palette = deepcopy(cfg_before.get("appearance", {}).get("palette", {}))
    resolved = _resolve_request(request, cfg_before, preview=False)

    cfg = deepcopy(cfg_before)
    _apply_ui_snapshot_to_cfg(cfg, resolved.get("ui"))
    wallpaper_path = resolved["wallpaper"]
    if wallpaper_path:
        cfg.setdefault("background", {})["wallpaperPath"] = wallpaper_path

    # A video thumbnail is needed even when the color source itself is preset/custom.
    source_image = resolved.get("sourceImage") or ""
    if wallpaper_path and _is_video(wallpaper_path):
        if not source_image:
            source_image = _source_image_for_wallpaper(wallpaper_path, cfg_before, preview=False)
        cfg.setdefault("background", {})["thumbnailPath"] = source_image
    elif wallpaper_path and not source_image:
        source_image = wallpaper_path

    if targets.get("shell", True):
        cfg.setdefault("appearance", {}).setdefault("palette", {})["type"] = resolved["scheme"]
        cfg["appearance"]["palette"]["accentColor"] = (
            resolved["seed"] if resolved["source"] in {"preset", "custom"} else ""
        )

    _update_engine_flags(cfg, targets)
    _write_json(NYVOREL_CONFIG, cfg)

    # Matugen renders all configured outputs. Capture disabled targets first and
    # restore them after successful generation so target isolation is exact.
    preserve = _capture_files(_files_for_disabled_targets(targets))

    if resolved["source"] == "hybrid":
        base = resolved["hybridBase"]
        _run_switchwall(resolved["baseMode"], base["scheme"], base["seed"], targets=targets)
        base_colors = _read_json(COLORS_JSON, {})
        _run_switchwall(resolved["baseMode"], resolved["resolvedScheme"], resolved["seed"], targets=targets)
        accent_colors = _read_json(COLORS_JSON, {})
        if targets.get("shell", True):
            _write_json(COLORS_JSON, _merge_hybrid_surfaces(base_colors, accent_colors))
    else:
        _run_switchwall(resolved["baseMode"], resolved["resolvedScheme"], resolved["seed"], targets=targets)
        if (
            resolved["source"] == "custom"
            and _II_CUSTOM_PALETTE_ANCHORS
            and targets.get("shell", True)
        ):
            # switchwall still renders enabled external targets from the Primary seed.
            # Quickshell owns the full semantic role map, so restore the four-anchor merge.
            _write_json(
                COLORS_JSON,
                _generate_palette(
                    resolved["seed"],
                    resolved["resolvedScheme"],
                    resolved["baseMode"],
                ),
            )

    if targets.get("shell", True):
        _apply_special_mode(resolved["mode"])

    _restore_files(preserve)

    # switchwall --color intentionally does not own wallpaper selection. Put the
    # committed wallpaper/UI semantics back into II's authoritative config.
    cfg_after = _read_json(NYVOREL_CONFIG, {})
    _apply_ui_snapshot_to_cfg(cfg_after, resolved.get("ui"))
    if wallpaper_path:
        cfg_after.setdefault("background", {})["wallpaperPath"] = wallpaper_path
        if _is_video(wallpaper_path):
            cfg_after["background"]["thumbnailPath"] = source_image

    if targets.get("shell", True):
        cfg_after.setdefault("appearance", {}).setdefault("palette", {})["type"] = resolved["scheme"]
        cfg_after["appearance"]["palette"]["accentColor"] = (
            resolved["seed"] if resolved["source"] in {"preset", "custom"} else ""
        )
    else:
        cfg_after.setdefault("appearance", {})["palette"] = previous_palette

    _update_engine_flags(cfg_after, targets)
    _ensure_radius_geometry(cfg_after)
    _write_json(NYVOREL_CONFIG, cfg_after)
    _sync_hyprland_window_radius(cfg_after, persist=True)
    _sync_glass_runtime_for_cfg(cfg_after)

    # Keep consumers that still read generated/wallpaper/path.txt coherent. For
    # videos, expose the extracted image frame rather than a media file.
    if source_image:
        WALLPAPER_TXT.parent.mkdir(parents=True, exist_ok=True)
        WALLPAPER_TXT.write_text(str(source_image) + "\n")

    if wallpaper_path and wallpaper_path != previous_wallpaper:
        _apply_wallpaper_runtime(wallpaper_path, cfg_after)

    active_ui = _config_snapshot()
    active = _make_active(
        resolved["source"],
        resolved["mode"],
        resolved["scheme"],
        wallpaper_path,
        resolved["preset"],
        resolved["seed"],
        _detect_ui_profile(cfg_after),
    )

    state = _load_state()
    state["active"] = active
    state["activeUi"] = deepcopy(active_ui)
    state["preview"] = None
    if record_history:
        entry = _history_entry(active, active_ui, _read_json(COLORS_JSON, {}))
        fp = entry.get("fingerprint")
        existing = []
        for item in state.get("history", []):
            item_fp = item.get("fingerprint") or _appearance_fingerprint(item.get("active", {}), item.get("ui", {}))
            if item_fp != fp:
                existing.append(item)
        state["history"] = [entry] + existing[:19]
    _save_state(state)

    warnings = _run_post_commit_integrations(
        targets,
        resolved_scheme=resolved["resolvedScheme"],
    )
    notes: list[str] = []
    if resolved["source"] == "hybrid":
        notes.append("Hybrid preset surfaces are merged into the Quickshell palette; external targets use the wallpaper accent palette.")
    if resolved["mode"] in {"oled", "dim", "high-contrast"}:
        notes.append("OLED, Dim, and High Contrast are Quickshell surface treatments; external targets use the dark Material base.")

    return {
        "ok": True,
        "active": active,
        "preview": False,
        "previewTimeout": 0,
        "resolvedScheme": resolved["resolvedScheme"],
        "warnings": warnings,
        "notes": notes,
    }

def apply_theme(
    *,
    source: str,
    mode: str,
    scheme: str,
    preset: str = "",
    seed: str = "",
    wallpaper: str = "",
    preview: bool = False,
    record_history: bool = True,
    ui_snapshot: dict[str, Any] | None = None,
) -> dict[str, Any]:
    request = _theme_request(
        source=source,
        mode=mode,
        scheme=scheme,
        preset=preset,
        seed=seed,
        wallpaper=wallpaper,
        ui_snapshot=ui_snapshot,
    )

    current_state = _reconcile_state_before_mutation(_load_state())
    if not preview and current_state.get("preview"):
        raise RuntimeError("A preview is active; Keep or Revert it before applying another appearance")

    if preview:
        state = current_state
        previous_runtime = _transaction_snapshot()
        existing = state.get("preview") or {}
        had_valid_session = bool(
            existing
            and PREVIEW_DIR.is_dir()
            and (PREVIEW_DIR / "manifest.json").is_file()
            and (PREVIEW_DIR / "state-before.json").is_file()
        )

        try:
            if had_valid_session:
                # Always start a new revision from the immutable committed
                # baseline, never from the previous preview revision.
                _restore_preview_runtime(remove=False)
                _sync_persistent_target_flags(state)
                token = str(existing.get("token") or uuid.uuid4().hex)
                revision = int(existing.get("revision", 0)) + 1
            else:
                if PREVIEW_DIR.exists():
                    shutil.rmtree(PREVIEW_DIR, ignore_errors=True)
                _prepare_preview_snapshot(state)
                token = uuid.uuid4().hex
                revision = 1

            # Persist a provisional revision *before* touching the preview
            # runtime. If this process is killed mid-render, the watchdog still
            # has a token/revision and can restore the immutable baseline.
            provisional_now = time.time()
            preview_state = {
                "token": token,
                "revision": revision,
                "started": int(existing.get("started", provisional_now)) if had_valid_session else int(provisional_now),
                "updated": int(provisional_now),
                "expiresAt": provisional_now + PREVIEW_TIMEOUT_SECONDS,
                "timeoutSeconds": PREVIEW_TIMEOUT_SECONDS,
                "candidate": deepcopy(existing.get("candidate")) if had_valid_session else None,
                "request": request,
                "resolvedScheme": existing.get("resolvedScheme", "") if had_valid_session else "",
                "status": "rendering",
            }
            state = deepcopy(state)
            state["preview"] = preview_state
            _save_state(state)
            _launch_preview_watchdog(token, revision)

            rendered = _render_preview(request)
            now = time.time()
            preview_state.update({
                "updated": int(now),
                "expiresAt": now + PREVIEW_TIMEOUT_SECONDS,
                "candidate": deepcopy(rendered["active"]),
                "resolvedScheme": rendered["resolved"]["resolvedScheme"],
                "status": "active",
            })

            # state.active and state.activeUi remain the committed baseline.
            state["preview"] = preview_state
            _save_state(state)
            # A second watchdog launch is intentional. The provisional one may
            # have timed out waiting for the mutation lock during a slow render;
            # duplicate healthy watchdogs are harmless because token+revision
            # checks make only one of them capable of reverting.
            _launch_preview_watchdog(token, revision)

            return {
                "ok": True,
                "active": rendered["active"],
                "preview": True,
                "previewTimeout": PREVIEW_TIMEOUT_SECONDS,
                "previewState": preview_state,
                "resolvedScheme": rendered["resolved"]["resolvedScheme"],
            }
        except Exception:
            # A failed revision leaves the previously visible preview exactly as
            # it was. First-preview failure restores the committed desktop.
            _restore_transaction(previous_runtime)
            if not had_valid_session:
                shutil.rmtree(PREVIEW_DIR, ignore_errors=True)
            raise

    transaction = _transaction_snapshot()
    previous_cfg = _read_json(NYVOREL_CONFIG, {})
    previous_wallpaper = _current_wallpaper(previous_cfg)
    requested_wallpaper = str(_local_path(wallpaper)) if wallpaper else previous_wallpaper
    wallpaper_may_change = bool(requested_wallpaper and requested_wallpaper != previous_wallpaper)
    try:
        return _apply_theme_core(
            source=source,
            mode=mode,
            scheme=scheme,
            preset=preset,
            seed=seed,
            wallpaper=wallpaper,
            preview=False,
            record_history=record_history,
            ui_snapshot=ui_snapshot,
        )
    except Exception:
        _restore_transaction(transaction)
        if wallpaper_may_change and previous_wallpaper:
            _apply_wallpaper_runtime(
                previous_wallpaper,
                _read_json(NYVOREL_CONFIG, previous_cfg),
                best_effort=True,
            )
        raise

def keep_preview() -> dict[str, Any]:
    state = _load_state()
    preview = state.get("preview") or {}
    if not preview:
        return {"ok": True, "message": "No preview is active"}

    request = deepcopy(preview.get("request") or {})
    if not request:
        raise RuntimeError("Preview request is missing; revert the preview and try again")

    # Capture the currently visible preview so a failed Keep can put it back.
    preview_runtime = _transaction_snapshot()
    state_with_preview = deepcopy(state)
    baseline = _baseline_state_preserving_globals(state)
    baseline_wallpaper = str(baseline.get("active", {}).get("wallpaper", "") or "")

    try:
        _restore_preview_runtime(remove=False)
        _sync_persistent_target_flags(baseline)
        _save_state(baseline)

        result = _apply_theme_core(
            source=request.get("source", "wallpaper"),
            mode=request.get("mode", "dark"),
            scheme=request.get("scheme", "auto"),
            preset=request.get("preset", ""),
            seed=_ii_custom_seed_transport(
                request.get("seed", ""),
                request.get("customPalette"),
            ),
            wallpaper=request.get("wallpaper", ""),
            preview=False,
            record_history=True,
            ui_snapshot=request.get("ui") or {},
        )
        shutil.rmtree(PREVIEW_DIR, ignore_errors=True)
        result["keptPreview"] = True
        return result
    except Exception:
        # Keep is atomic from the user's perspective. If committing the latest
        # draft fails, restore the previous preview and give it a fresh timeout.
        _restore_transaction(preview_runtime)
        if baseline_wallpaper:
            _apply_wallpaper_runtime(
                baseline_wallpaper,
                _read_json(NYVOREL_CONFIG, {}),
                best_effort=True,
            )

        restored = _load_state()
        restored_preview = deepcopy(restored.get("preview") or state_with_preview.get("preview") or {})
        token = str(restored_preview.get("token") or uuid.uuid4().hex)
        revision = int(restored_preview.get("revision", 0)) + 1
        now = time.time()
        restored_preview["token"] = token
        restored_preview["revision"] = revision
        restored_preview["updated"] = int(now)
        restored_preview["expiresAt"] = now + PREVIEW_TIMEOUT_SECONDS
        restored_preview["timeoutSeconds"] = PREVIEW_TIMEOUT_SECONDS
        restored["preview"] = restored_preview
        _save_state(restored)
        _launch_preview_watchdog(token, revision)
        raise

def revert_preview() -> dict[str, Any]:
    state = _load_state()
    if not PREVIEW_DIR.exists():
        state["preview"] = None
        _save_state(state)
        return {"ok": True, "message": "No preview snapshot was found"}

    baseline = _baseline_state_preserving_globals(state)
    _restore_preview_runtime(remove=True)
    _sync_persistent_target_flags(baseline)
    _save_state(baseline)
    return {"ok": True, "reverted": True, "active": baseline.get("active", {})}


def apply_ui_profile(profile_id: str) -> dict[str, Any]:
    # Backward-compatible direct CLI action. Legacy `mica` now resolves to Inlay.
    profile_id = LEGACY_UI_PROFILE_ALIASES.get(profile_id, profile_id)
    # The v0.3 QML stages profiles as draft UI and commits them through
    # apply/preview instead.
    if profile_id not in UI_PROFILES:
        raise RuntimeError(f"Unknown UI profile: {profile_id}")

    transaction = _transaction_snapshot()
    try:
        cfg = _read_json(NYVOREL_CONFIG, {})
        _ensure_radius_geometry(cfg)
        for key, value in UI_PROFILES[profile_id]["patch"].items():
            _set_nested(cfg, key, value)
        _write_json(NYVOREL_CONFIG, cfg)
        _sync_hyprland_window_radius(cfg, persist=True)
        _sync_glass_runtime_for_cfg(cfg)
        state = _load_state()
        state.setdefault("active", {})["uiProfile"] = profile_id
        state["activeUi"] = _config_snapshot()
        _save_state(state)
        return {"ok": True, "uiProfile": profile_id}
    except Exception:
        _restore_transaction(transaction)
        raise

def _sync_persistent_target_flags(state: dict[str, Any]) -> None:
    cfg = _read_json(NYVOREL_CONFIG, {})
    theming = cfg.setdefault("appearance", {}).setdefault("wallpaperTheming", {})
    targets = state.get("targets", {})
    theming["enableQtApps"] = bool(targets.get("qt", True))
    theming["enableTerminal"] = bool(targets.get("terminal", True))
    _write_json(NYVOREL_CONFIG, cfg)



def set_target(name: str, enabled: bool) -> dict[str, Any]:
    state = _reconcile_state_before_mutation(_load_state())
    if name not in state["targets"]:
        raise RuntimeError(f"Unknown target: {name}")

    previous = bool(state["targets"].get(name, True))
    state["targets"][name] = enabled
    _save_state(state)

    if name in {"qt", "terminal"}:
        cfg = _read_json(NYVOREL_CONFIG, {})
        key = "enableQtApps" if name == "qt" else "enableTerminal"
        cfg.setdefault("appearance", {}).setdefault("wallpaperTheming", {})[key] = enabled
        _write_json(NYVOREL_CONFIG, cfg)

    warnings: list[str] = []

    if enabled and not previous:
        active, active_ui = _runtime_committed_view(state)
        result = apply_theme(
            source=active.get("source", "wallpaper"),
            mode=active.get("mode", "dark"),
            scheme=active.get("scheme", "auto"),
            preset=active.get("preset", ""),
            seed=active.get("seed", ""),
            wallpaper=active.get("wallpaper", ""),
            preview=False,
            record_history=False,
            ui_snapshot=active_ui,
        )
        warnings = list(result.get("warnings", []))

    return {
        "ok": True,
        "target": name,
        "enabled": enabled,
        "synchronized": bool(enabled and not previous),
        "warnings": warnings,
    }


def add_favorite(label: str = "") -> dict[str, Any]:
    state = _reconcile_state_before_mutation(_load_state())
    if state.get("preview"):
        raise RuntimeError("Keep or Revert the preview before saving a favorite")

    active, active_ui = _runtime_committed_view(state)
    active["uiProfile"] = active.get("uiProfile") or _detect_ui_profile()

    entry = _history_entry(active, active_ui, _read_json(COLORS_JSON, {}))
    entry["id"] = uuid.uuid4().hex[:12]

    if label:
        entry["label"] = label
        entry["customLabel"] = True

    existing: list[dict[str, Any]] = []
    entry_fp = entry.get("fingerprint")
    entry_label = entry.get("label")

    for favorite in state.get("favorites", []):
        favorite_fp = favorite.get("fingerprint") or _appearance_fingerprint(
            favorite.get("active", {}),
            favorite.get("ui", {}),
        )
        same_exact_favorite = (
            favorite_fp == entry_fp
            and favorite.get("label") == entry_label
        )
        if not same_exact_favorite:
            existing.append(favorite)

    state["favorites"] = [entry] + existing[:29]
    _save_state(state)
    return {"ok": True, "favorite": entry}

def _apply_saved(entry: dict[str, Any]) -> dict[str, Any]:
    if _load_state().get("preview"):
        raise RuntimeError("Keep or Revert the preview before restoring a saved appearance")
    # Target toggles are global integration preferences. Restoring a visual
    # favorite/history entry must not silently enable/disable GTK, Qt, etc.
    active = entry["active"]
    return apply_theme(
        source=active.get("source", "wallpaper"),
        mode=active.get("mode", "dark"),
        scheme=active.get("scheme", "auto"),
        preset=active.get("preset", ""),
        seed=_ii_custom_seed_transport(
            active.get("seed", ""),
            active.get("customPalette"),
        ),
        wallpaper=active.get("wallpaper", ""),
        preview=False,
        record_history=True,
        ui_snapshot=entry.get("ui") or {},
    )


def apply_favorite(item_id: str) -> dict[str, Any]:
    state = _load_state()
    entry = next((f for f in state.get("favorites", []) if f.get("id") == item_id), None)
    if not entry:
        raise RuntimeError("Favorite not found")
    return _apply_saved(entry)


def remove_favorite(item_id: str) -> dict[str, Any]:
    state = _load_state()
    state["favorites"] = [f for f in state.get("favorites", []) if f.get("id") != item_id]
    _save_state(state)
    return {"ok": True}


def apply_history(item_id: str) -> dict[str, Any]:
    state = _load_state()
    entry = next((h for h in state.get("history", []) if h.get("id") == item_id), None)
    if not entry:
        raise RuntimeError("History item not found")
    return _apply_saved(entry)


def variant_palettes(wallpaper: str, mode: str) -> dict[str, Any]:
    cfg = _read_json(NYVOREL_CONFIG, {})
    wallpaper = wallpaper or _current_wallpaper(cfg)
    if not wallpaper or not _local_path(wallpaper).is_file():
        return {"ok": True, "sourceColor": "", "variants": [], "error": "Wallpaper is unavailable"}

    try:
        source_image = _source_image_for_wallpaper(wallpaper, cfg, preview=True)
        base_mode = _resolve_base_mode(mode, source_image)
    except Exception as exc:
        return {"ok": True, "sourceColor": "", "variants": [], "error": str(exc)}

    names = dict(SCHEMES)
    data = []
    errors = []

    try:
        matrix = _smart_wallpaper_matrix(source_image, base_mode, mode)
        global_best = matrix["best"]

        for scheme_id, _ in SCHEMES:
            if scheme_id == "auto":
                continue

            options = [
                item
                for item in matrix["evaluations"]
                if item.get("scheme") == scheme_id
            ]
            if not options:
                errors.append(f"{scheme_id}: no generated candidate")
                continue

            choice = max(options, key=lambda item: item["score"])
            full = choice.get("visiblePalette") or choice.get("palette") or {}

            data.append({
                "id": scheme_id,
                "name": names.get(scheme_id, scheme_id),
                "seed": choice["seed"],
                "score": choice["score"],
                "reason": choice.get("reason", ""),
                "metrics": deepcopy(choice.get("metrics", {})),
                "colors": {
                    "primary": full.get("primary"),
                    "secondary": full.get("secondary"),
                    "tertiary": full.get("tertiary"),
                    "surface": full.get("surface_container", full.get("surface")),
                    "onSurface": full.get("on_surface"),
                },
            })

        auto_scheme = global_best["scheme"]
        auto_seed = global_best["seed"]
        auto_source = next(
            (
                item
                for item in data
                if item.get("id") == auto_scheme
                and item.get("seed") == auto_seed
            ),
            None,
        )
        if auto_source is None:
            auto_source = next(
                (item for item in data if item.get("id") == auto_scheme),
                None,
            )

        if auto_source:
            auto_item = deepcopy(auto_source)
            auto_item["id"] = "auto"
            auto_item["name"] = "Auto"
            auto_item["resolvedScheme"] = auto_scheme
            auto_item["resolvedSeed"] = auto_seed
            auto_item["score"] = global_best.get("score")
            auto_item["reason"] = global_best.get("reason", "")
            auto_item["metrics"] = deepcopy(global_best.get("metrics", {}))
            data = [auto_item] + data

        error = ""
        if not data:
            error = "Variant generation failed. " + " | ".join(errors[:3])
        elif errors:
            error = f"{len(errors)} variant preview(s) could not be generated"

        return {
            "ok": True,
            "wallpaper": wallpaper,
            "sourceImage": source_image,
            "sourceColor": auto_seed,
            "baseMode": base_mode,
            "autoScheme": auto_scheme,
            "variants": data,
            "error": error,
            "intelligence": {
                "engine": "semantic-palette-score-v1",
                "candidateSeeds": matrix.get("seeds", []),
                "profile": matrix.get("profile", {}),
                "autoScore": global_best.get("score"),
                "autoReason": global_best.get("reason", ""),
                "errors": matrix.get("errors", []),
            },
        }

    except Exception as smart_exc:
        try:
            seed = _source_color_from_image(source_image)
        except Exception as exc:
            return {
                "ok": True,
                "sourceColor": "",
                "variants": [],
                "error": str(exc),
            }

        for scheme_id, _ in SCHEMES:
            if scheme_id == "auto":
                continue
            try:
                full = _generate_palette(seed, scheme_id, base_mode)
                full = _apply_special_mode_colors(full, mode)
                data.append({
                    "id": scheme_id,
                    "name": names.get(scheme_id, scheme_id),
                    "colors": {
                        "primary": full.get("primary"),
                        "secondary": full.get("secondary"),
                        "tertiary": full.get("tertiary"),
                        "surface": full.get("surface_container", full.get("surface")),
                        "onSurface": full.get("on_surface"),
                    },
                })
            except Exception as exc:
                errors.append(f"{scheme_id}: {exc}")

        auto_scheme = _resolve_scheme("auto", source_image)
        auto_source = next(
            (item for item in data if item.get("id") == auto_scheme),
            None,
        )
        if auto_source:
            auto_item = deepcopy(auto_source)
            auto_item["id"] = "auto"
            auto_item["name"] = "Auto"
            auto_item["resolvedScheme"] = auto_scheme
            data = [auto_item] + data

        error = ""
        if not data:
            error = "Variant generation failed. " + " | ".join(errors[:3])
        elif errors:
            error = f"{len(errors)} variant preview(s) could not be generated"

        return {
            "ok": True,
            "wallpaper": wallpaper,
            "sourceImage": source_image,
            "sourceColor": seed,
            "baseMode": base_mode,
            "autoScheme": auto_scheme,
            "variants": data,
            "error": error,
            "intelligence": {
                "engine": "legacy-fallback",
                "warning": str(smart_exc),
            },
        }

def status() -> dict[str, Any]:
    state = _load_state()
    cfg = _read_json(NYVOREL_CONFIG, {})
    colors = _read_json(COLORS_JSON, {})
    active, committed_ui = _runtime_committed_view(state, cfg)

    # During preview Config contains the temporary draft, while the runtime
    # committed view above intentionally remains the pre-preview baseline.

    return {
        "ok": True,
        "version": STATE_VERSION,
        "studioVersion": STUDIO_VERSION,
        "wallpaper": cfg.get("background", {}).get("wallpaperPath", ""),
        "committedWallpaper": active.get("wallpaper", ""),
        "thumbnail": cfg.get("background", {}).get("thumbnailPath", ""),
        "palette": cfg.get("appearance", {}).get("palette", {}),
        "colors": colors,
        "active": active,
        "activeUi": committed_ui,
        "currentFingerprint": _appearance_fingerprint(active, committed_ui),
        "targets": state.get("targets", {}),
        "favorites": state.get("favorites", []),
        "history": state.get("history", []),
        "preview": state.get("preview"),
        "previewTimeout": PREVIEW_TIMEOUT_SECONDS,
        "presets": PRESETS,
        "schemes": [{"id": value, "name": name} for value, name in SCHEMES],
        "modes": [{"id": value, "name": name} for value, name in MODES],
        "uiProfiles": [
            {
                "id": key,
                "name": value["name"],
                "description": value["description"],
                "patch": deepcopy(value["patch"]),
            }
            for key, value in UI_PROFILES.items()
        ],
        # `ui` is what is currently rendered: draft during preview, committed otherwise.
        "ui": _config_snapshot(),
        "geometry": {
            "global": _resolved_radius(cfg, "global"),
            **{role: _resolved_radius(cfg, role) for role in RADIUS_ROLES},
        },
        "semantics": {
            "previewScope": "quickshell-and-interface-only",
            "hybridExternalTargets": "wallpaper-accent",
            "specialModesExternalTargets": "dark-material-base",
        },
    }

def _print(data: dict[str, Any]) -> None:
    print(json.dumps(data, ensure_ascii=False))


def _parse_ui_json(raw: str) -> dict[str, Any]:
    if not raw:
        return {}
    try:
        value = json.loads(raw)
    except Exception as exc:
        raise RuntimeError(f"Invalid UI draft JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise RuntimeError("UI draft must be a JSON object")
    return value


def _execute(args: argparse.Namespace) -> dict[str, Any]:
    if args.command == "status":
        return status()
    if args.command == "variants":
        return variant_palettes(args.wallpaper, args.mode)
    if args.command == "apply":
        return apply_theme(
            source=args.source,
            mode=args.mode,
            scheme=args.scheme,
            preset=args.preset,
            seed=args.seed,
            wallpaper=args.wallpaper,
            preview=args.preview,
            record_history=not args.preview,
            ui_snapshot=_parse_ui_json(args.ui_json),
        )
    if args.command == "preview-watchdog":
        return preview_watchdog(args.token, args.revision)
    if args.command == "keep-preview":
        return keep_preview()
    if args.command == "revert-preview":
        return revert_preview()
    if args.command == "ui-profile":
        return apply_ui_profile(args.id)
    if args.command == "target":
        return set_target(args.name, args.enabled in {"true", "1"})
    if args.command == "favorite-add":
        return add_favorite(args.label)
    if args.command == "favorite-remove":
        return remove_favorite(args.id)
    if args.command == "favorite-apply":
        return apply_favorite(args.id)
    if args.command == "history-apply":
        return apply_history(args.id)
    if args.command == "clear-history":
        state = _load_state()
        state["history"] = []
        _save_state(state)
        return {"ok": True}
    raise RuntimeError("Unsupported command")


def main() -> int:
    parser = argparse.ArgumentParser(description="Nyvorel Appearance Studio controller")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("status")

    p = sub.add_parser("variants")
    p.add_argument("--wallpaper", default="")
    p.add_argument("--mode", default="dark", choices=[x[0] for x in MODES])

    p = sub.add_parser("apply")
    p.add_argument("--source", choices=["wallpaper", "preset", "custom", "hybrid"], default="wallpaper")
    p.add_argument("--mode", choices=[x[0] for x in MODES], default="dark")
    p.add_argument("--scheme", choices=[x[0] for x in SCHEMES], default="auto")
    p.add_argument("--preset", default="")
    p.add_argument("--seed", default="")
    p.add_argument("--wallpaper", default="")
    p.add_argument("--ui-json", default="")
    p.add_argument("--preview", action="store_true")

    p = sub.add_parser("preview-watchdog")
    p.add_argument("--token", required=True)
    p.add_argument("--revision", required=True, type=int)

    sub.add_parser("keep-preview")
    sub.add_parser("revert-preview")

    # Kept for CLI/backward compatibility. The v0.3 QML stages UI profiles
    # locally and commits them through --ui-json.
    p = sub.add_parser("ui-profile")
    p.add_argument("id", choices=sorted(set(UI_PROFILES) | set(LEGACY_UI_PROFILE_ALIASES)))

    p = sub.add_parser("target")
    p.add_argument("name", choices=["shell", "hyprland", "hyprlock", "gtk", "fuzzel", "qt", "terminal", "editors"])
    p.add_argument("enabled", choices=["true", "false", "1", "0"])

    p = sub.add_parser("favorite-add")
    p.add_argument("--label", default="")
    p = sub.add_parser("favorite-remove")
    p.add_argument("id")
    p = sub.add_parser("favorite-apply")
    p.add_argument("id")
    p = sub.add_parser("history-apply")
    p.add_argument("id")
    sub.add_parser("clear-history")

    args = parser.parse_args()
    try:
        if args.command in {"status", "variants", "preview-watchdog"}:
            result = _execute(args)
        else:
            with _mutation_lock():
                result = _execute(args)
        _print(result)
        return 0
    except Exception as exc:
        _print({"ok": False, "error": str(exc)})
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
