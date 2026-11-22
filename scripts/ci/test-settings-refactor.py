#!/usr/bin/env python3
"""Check Settings search routing and the Quickshell lock paths."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
INDEX = ROOT / "quickshell/modules/nyvorel/settingsControlRail/SettingsSearchIndex.js"
PAGES = [
    "Appearance", "Bar & workspaces", "Desktop", "Windows & controls",
    "System & language", "Services", "About",
]


def check_search() -> None:
    source = INDEX.read_text(encoding="utf-8")
    entries = json.loads(source.split("var entries = ", 1)[1].strip()[:-1])
    assert len({entry["id"] for entry in entries}) == len(entries), "duplicate setting ID"
    actions = [entry for entry in entries if "action" in entry]
    assert len(actions) == 1 and actions[0]["action"] == "open-config"
    assert "pageIndex" not in actions[0], "Opening the configuration should not navigate to a page"
    pages = [entry for entry in entries if "action" not in entry]
    for entry in pages:
        assert 0 <= entry["pageIndex"] < len(PAGES), entry
        assert entry["page"] == PAGES[entry["pageIndex"]], entry
        if entry["path"] == "Page":
            assert entry["label"] == entry["page"], entry
        else:
            assert not entry["path"].endswith("Config"), entry
    assert {entry["pageIndex"] for entry in pages} == set(range(len(PAGES)))
    labels = {entry["label"] for entry in entries}
    assert "Open Appearance Studio" not in labels
    assert "Lock provider" not in labels and "Hyprlock" not in labels
    assert "Change wallpaper" in labels
    assert "Monochrome app icons" in labels
    assert "Keyboard layout" in labels
    assert "Shell language" in labels
    for label in ("Arch Remote", "Backup & Recovery"):
        assert any(entry["label"] == label and entry.get("pageSection") == "optional-tools" for entry in entries)
    assert any(entry["label"] == "Screen edges" and entry.get("appearanceSection") == "screen"
               for entry in entries)
    assert "Quick sliders" not in labels
    assert "Konachan" not in labels


def check_lock_paths() -> None:
    command = "qs -c nyvorel ipc call lock activate"
    binding = (ROOT / "hypr/hyprland.lua").read_text()
    idle = (ROOT / "hypr/hypridle.conf").read_text()
    lock = (ROOT / "quickshell/modules/common/panels/lock/LockScreen.qml").read_text()
    settings = (ROOT / "quickshell/modules/settings/GeneralConfig.qml").read_text()
    assert f'hl.bind("SUPER + L", hl.dsp.exec_cmd("{command}")' in binding
    assert f"$lock_cmd = {command}" in idle
    assert "before_sleep_cmd = $lock_cmd" in idle
    assert 'target: "lock"' in lock and "GlobalStates.screenLocked = true" in lock
    assert "hyprlock" not in lock
    for value in ("hh:mm", "h:mm ap", "h:mm AP"):
        assert f'onClicked: Config.options.time.format = "{value}"' in settings


if __name__ == "__main__":
    check_search()
    check_lock_paths()
    print("Settings routes and Quickshell lock paths passed")
