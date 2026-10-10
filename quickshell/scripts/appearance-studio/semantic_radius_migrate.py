#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
from pathlib import Path
from typing import Callable

HOME = Path.home()
XDG_CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config"))
II = XDG_CONFIG / "quickshell/nyvorel"
CONFIG_QML = II / "modules/common/Config.qml"
APPEARANCE_QML = II / "modules/common/Appearance.qml"
NYVOREL_CONFIG = XDG_CONFIG / "nyvorel/config.json"
HYPR_CUSTOM_GENERAL = XDG_CONFIG / "hypr/custom/appearance-runtime.lua" if (XDG_CONFIG / "hypr/hyprland.lua").is_file() else XDG_CONFIG / "hypr/custom/appearance-runtime.conf"

RADIUS_DEFAULTS = {
    "global": 17,
    "window": {"followGlobal": False, "value": 8},
    "modal": {"followGlobal": False, "value": 23},
    "sidebar": {"followGlobal": False, "value": 23},
    "popup": {"followGlobal": True, "value": 17},
    "card": {"followGlobal": True, "value": 17},
    "control": {"followGlobal": False, "value": 12},
    "screen": {"followGlobal": False, "value": 8},
}
ROLES = ("window", "modal", "sidebar", "popup", "card", "control", "screen")

SURFACE_FILES = [
    "modules/nyvorel/sidebarLeft/SidebarLeft.qml",
    "modules/nyvorel/sidebarRight/SidebarRightContent.qml",
    "modules/nyvorel/bar/StyledPopup.qml",
    "modules/nyvorel/bar/BatteryPopup.qml",
    "modules/nyvorel/bar/ClockWidgetPopup.qml",
    "modules/nyvorel/bar/ResourcesPopup.qml",
    "modules/nyvorel/bar/SysTrayMenu.qml",
    "modules/common/widgets/WindowDialog.qml",
    "modules/common/widgets/SelectionDialog.qml",
    "modules/common/widgets/NotificationGroup.qml",
    "modules/nyvorel/sidebarRight/BottomWidgetGroup.qml",
    "modules/nyvorel/sidebarRight/CenterWidgetGroup.qml",
    "modules/nyvorel/sidebarRight/QuickSliders.qml",
    "modules/nyvorel/sidebarRight/quickToggles/AbstractQuickPanel.qml",
    "modules/nyvorel/sidebarRight/notifications/NotificationList.qml",
    "modules/nyvorel/wallpaperSelector/WallpaperSelectorContent.qml",
    "modules/nyvorel/onScreenDisplay/OsdValueIndicator.qml",
    "modules/nyvorel/overlay/OverlayTaskbar.qml",
    "ReloadPopup.qml",
]


def load_json(path: Path, default):
    try:
        return json.loads(path.read_text())
    except Exception:
        return default


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    tmp.replace(path)


def ensure_json_geometry() -> bool:
    cfg = load_json(NYVOREL_CONFIG, {})
    appearance = cfg.setdefault("appearance", {})
    geometry = appearance.setdefault("geometry", {})
    radius = geometry.setdefault("radius", {})
    before = json.dumps(radius, sort_keys=True)
    radius.setdefault("global", RADIUS_DEFAULTS["global"])
    for role in ROLES:
        d = RADIUS_DEFAULTS[role]
        item = radius.get(role)
        if not isinstance(item, dict):
            item = {}
            radius[role] = item
        item.setdefault("followGlobal", d["followGlobal"])
        item.setdefault("value", d["value"])
    after = json.dumps(radius, sort_keys=True)
    if before != after:
        write_json(NYVOREL_CONFIG, cfg)
        return True
    return False


def patch_config_qml() -> bool:
    if not CONFIG_QML.is_file():
        raise RuntimeError(f"Missing {CONFIG_QML}")
    text = CONFIG_QML.read_text()
    if "property JsonObject geometry: JsonObject" in text and "property JsonObject radius: JsonObject" in text:
        return False

    anchor = '                property int fakeScreenRounding: 2 // 0: None | 1: Always | 2: When not fullscreen\n'
    if anchor not in text:
        raise RuntimeError("Could not find appearance.fakeScreenRounding anchor in Config.qml")

    block = anchor + '''                // Semantic corner geometry. Low-level size tokens stay available in Appearance.rounding,\n                // while shell surfaces consume these role-based values.\n                property JsonObject geometry: JsonObject {\n                    property JsonObject radius: JsonObject {\n                        property int global: 17\n                        property JsonObject window: JsonObject { property bool followGlobal: false; property int value: 8 }\n                        property JsonObject modal: JsonObject { property bool followGlobal: false; property int value: 23 }\n                        property JsonObject sidebar: JsonObject { property bool followGlobal: false; property int value: 23 }\n                        property JsonObject popup: JsonObject { property bool followGlobal: true; property int value: 17 }\n                        property JsonObject card: JsonObject { property bool followGlobal: true; property int value: 17 }\n                        property JsonObject control: JsonObject { property bool followGlobal: false; property int value: 12 }\n                        property JsonObject screen: JsonObject { property bool followGlobal: false; property int value: 8 }\n                    }\n                }\n'''
    CONFIG_QML.write_text(text.replace(anchor, block, 1))
    return True


def patch_appearance_qml() -> bool:
    if not APPEARANCE_QML.is_file():
        raise RuntimeError(f"Missing {APPEARANCE_QML}")
    text = APPEARANCE_QML.read_text()
    changed = False

    if "property QtObject radius" not in text:
        anchor = "    property QtObject rounding\n"
        if anchor not in text:
            raise RuntimeError("Could not find rounding property in Appearance.qml")
        text = text.replace(anchor, anchor + "    property QtObject radius\n", 1)
        changed = True

    if "radius: QtObject {" not in text:
        match = re.search(r"    rounding: QtObject \\{\\n.*?^    \\}\\n", text, re.S | re.M)
        if not match:
            raise RuntimeError("Could not find rounding block in Appearance.qml")
        semantic = match.group(0) + """
    // Semantic corner geometry. Legacy Appearance.rounding remains unchanged;
    // only explicitly migrated components consume these role-based values.
    radius: QtObject {
        readonly property int global: Math.max(0, Config.options.appearance.geometry.radius.global)
        readonly property int window: Config.options.appearance.geometry.radius.window.followGlobal ? global : Math.max(0, Config.options.appearance.geometry.radius.window.value)
        readonly property int modal: Config.options.appearance.geometry.radius.modal.followGlobal ? global : Math.max(0, Config.options.appearance.geometry.radius.modal.value)
        readonly property int sidebar: Config.options.appearance.geometry.radius.sidebar.followGlobal ? global : Math.max(0, Config.options.appearance.geometry.radius.sidebar.value)
        readonly property int popup: Config.options.appearance.geometry.radius.popup.followGlobal ? global : Math.max(0, Config.options.appearance.geometry.radius.popup.value)
        readonly property int card: Config.options.appearance.geometry.radius.card.followGlobal ? global : Math.max(0, Config.options.appearance.geometry.radius.card.value)
        readonly property int control: Config.options.appearance.geometry.radius.control.followGlobal ? global : Math.max(0, Config.options.appearance.geometry.radius.control.value)
        readonly property int screen: Config.options.appearance.geometry.radius.screen.followGlobal ? global : Math.max(0, Config.options.appearance.geometry.radius.screen.value)
        readonly property int full: root.rounding.full
    }
"""
        text = text[:match.start()] + semantic + text[match.end():]
        changed = True

    if changed:
        APPEARANCE_QML.write_text(text)
    return changed


def replace_once(path: Path, old: str, new: str) -> bool:
    if not path.is_file():
        return False
    text = path.read_text()
    if new in text:
        return False
    if old not in text:
        return False
    path.write_text(text.replace(old, new, 1))
    return True


def regex_once(path: Path, pattern: str, repl: str) -> bool:
    if not path.is_file():
        return False
    text = path.read_text()
    if repl in text:
        return False
    new, n = re.subn(pattern, repl, text, count=1, flags=re.S)
    if n:
        path.write_text(new)
        return True
    return False


def patch_surfaces() -> list[str]:
    changed: list[str] = []
    def mark(rel: str, result: bool):
        if result:
            changed.append(rel)

    # Sidebars: outer shell surfaces only.
    for rel in ("modules/nyvorel/sidebarLeft/SidebarLeft.qml", "modules/nyvorel/sidebarRight/SidebarRightContent.qml"):
        p = II / rel
        result = regex_once(
            p,
            r"Appearance\.rounding\.screenRounding\s*\n?\s*-\s*Appearance\.sizes\.hyprlandGapsOut\s*\n?\s*\+\s*1",
            "Appearance.radius.sidebar",
        )
        mark(rel, result)

    # Shared popup primitive plus the popups that explicitly overrode it.
    rel = "modules/nyvorel/bar/StyledPopup.qml"
    mark(rel, replace_once(II/rel, "Appearance.rounding.small", "Appearance.radius.popup"))
    for rel in ("modules/nyvorel/bar/BatteryPopup.qml", "modules/nyvorel/bar/ClockWidgetPopup.qml", "modules/nyvorel/bar/ResourcesPopup.qml"):
        mark(rel, replace_once(II/rel, "popupRadius:\n        Appearance.rounding.large", "popupRadius:\n        Appearance.radius.popup") or replace_once(II/rel, "popupRadius: Appearance.rounding.large", "popupRadius: Appearance.radius.popup"))

    rel = "modules/nyvorel/bar/SysTrayMenu.qml"
    mark(rel, replace_once(II/rel, "radius: Appearance.rounding.windowRounding", "radius: Appearance.radius.popup"))

    # Common dialogs: screen-sized wrapper and actual modal surface are distinct roles.
    rel = "modules/common/widgets/WindowDialog.qml"
    p = II/rel
    a = replace_once(p, "radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1", "radius: Appearance.radius.screen")
    b = replace_once(p, "radius: Appearance.rounding.large", "radius: Appearance.radius.modal")
    mark(rel, a or b)

    rel = "modules/common/widgets/SelectionDialog.qml"
    p = II/rel
    a = replace_once(p, "radius: Appearance.rounding.small", "radius: Appearance.radius.screen")
    b = replace_once(p, "radius: Appearance.rounding.normal", "radius: Appearance.radius.modal")
    mark(rel, a or b)

    # Notification card can be a popup or a card depending on mode.
    rel = "modules/common/widgets/NotificationGroup.qml"
    mark(rel, replace_once(II/rel, "radius:\n            Appearance.rounding.normal", "radius:\n            root.popup ? Appearance.radius.popup : Appearance.radius.card") or replace_once(II/rel, "radius: Appearance.rounding.normal", "radius: root.popup ? Appearance.radius.popup : Appearance.radius.card"))

    # Sidebar content groups are cards inside the outer sidebar shell.
    for rel in (
        "modules/nyvorel/sidebarRight/BottomWidgetGroup.qml",
        "modules/nyvorel/sidebarRight/CenterWidgetGroup.qml",
        "modules/nyvorel/sidebarRight/QuickSliders.qml",
        "modules/nyvorel/sidebarRight/quickToggles/AbstractQuickPanel.qml",
        "modules/nyvorel/sidebarRight/notifications/NotificationList.qml",
    ):
        mark(rel, replace_once(II/rel, "radius: Appearance.rounding.normal", "radius: Appearance.radius.card"))

    # Large selector surface.
    rel = "modules/nyvorel/wallpaperSelector/WallpaperSelectorContent.qml"
    mark(rel, replace_once(II/rel, "Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1", "Appearance.radius.modal"))

    # OSD main surface: only the audited outer 22px literal, not its internal indicators.
    rel = "modules/nyvorel/onScreenDisplay/OsdValueIndicator.qml"
    mark(rel, regex_once(II/rel, r"radius:\s*22\b", "radius: Appearance.radius.popup"))

    rel = "modules/nyvorel/overlay/OverlayTaskbar.qml"
    mark(rel, replace_once(II/rel, "radius: Appearance.rounding.large", "radius: Appearance.radius.popup"))

    # Quickshell reload toast popup.
    rel = "ReloadPopup.qml"
    mark(rel, regex_once(II/rel, r"radius:\s*12\b", "radius: Appearance.radius.popup"))

    return changed


def resolved_radius(cfg: dict, role: str) -> int:
    radius = cfg.get("appearance", {}).get("geometry", {}).get("radius", {})
    g = int(radius.get("global", 17))
    if role == "global":
        return g
    item = radius.get(role, {})
    return g if item.get("followGlobal", False) else int(item.get("value", RADIUS_DEFAULTS[role]["value"]))


def ensure_hypr_override() -> bool:
    cfg = load_json(NYVOREL_CONFIG, {})
    value = resolved_radius(cfg, "window")
    begin = "# >>> Appearance Studio: window radius >>>"
    end = "# <<< Appearance Studio: window radius <<<"
    block = f"{begin}\ndecoration {{\n    rounding = {value}\n}}\n{end}"
    text = HYPR_CUSTOM_GENERAL.read_text() if HYPR_CUSTOM_GENERAL.is_file() else ""
    pat = re.compile(re.escape(begin) + r".*?" + re.escape(end), re.S)
    if pat.search(text):
        new = pat.sub(block, text)
    else:
        sep = "" if not text else ("\n" if text.endswith("\n") else "\n\n")
        new = text + sep + block + "\n"
    if new != text:
        HYPR_CUSTOM_GENERAL.parent.mkdir(parents=True, exist_ok=True)
        HYPR_CUSTOM_GENERAL.write_text(new)
        return True
    return False


def check() -> int:
    failures: list[str] = []

    if not CONFIG_QML.is_file() or "property JsonObject geometry: JsonObject" not in CONFIG_QML.read_text():
        failures.append("Config.qml semantic geometry schema missing")

    if not APPEARANCE_QML.is_file():
        failures.append("Appearance.qml missing")
    else:
        text = APPEARANCE_QML.read_text()
        for token in (
            "property QtObject radius",
            "readonly property int modal",
            "readonly property int card",
            "readonly property int control",
        ):
            if token not in text:
                failures.append(f"Appearance.qml missing: {token}")

    cfg = load_json(NYVOREL_CONFIG, {})
    radius = cfg.get("appearance", {}).get("geometry", {}).get("radius", {})
    if not isinstance(radius, dict) or "global" not in radius:
        failures.append("config.json semantic radius object missing")

    studio = II / "modules/appearanceStudio/AppearanceStudio.qml"
    if studio.is_file():
        s = studio.read_text()
        for token in ("Appearance.radius.modal", "Appearance.radius.card", "Appearance.radius.control"):
            if token not in s:
                failures.append(f"Appearance Studio missing: {token}")

    print("Appearance Studio semantic-radius pilot")
    print(f"  global  = {resolved_radius(cfg, 'global')} px")
    print(f"  modal   = {resolved_radius(cfg, 'modal')} px")
    print(f"  card    = {resolved_radius(cfg, 'card')} px")
    print(f"  control = {resolved_radius(cfg, 'control')} px")
    print()

    if failures:
        for item in failures:
            print(f"  [FAIL] {item}")
        return 1

    print("  [OK] semantic radius engine is installed for Appearance Studio")
    return 0

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["apply", "check", "paths"])
    args = parser.parse_args()

    if args.command == "paths":
        # Phase 1 intentionally edits only the global schema/API.
        for p in (CONFIG_QML, APPEARANCE_QML, NYVOREL_CONFIG):
            print(p)
        return 0

    if args.command == "check":
        return check()

    changes = []
    if patch_config_qml(): changes.append("Config.qml")
    if patch_appearance_qml(): changes.append("Appearance.qml")
    if ensure_json_geometry(): changes.append("config.json")
    # Phase 1 stops here: no sidebar/popup/window/OSD/Hyprland migration.

    print(json.dumps({"ok": True, "changed": changes, "count": len(changes)}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
