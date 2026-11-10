#!/usr/bin/env python3
"""Check Settings search routing and the Hyprlock time-format transaction."""

import json
import os
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
INDEX = ROOT / "quickshell/modules/nyvorel/settingsControlRail/SettingsSearchIndex.js"
HELPER = ROOT / "quickshell/scripts/system/nyvorel-lock-time-format"
PAGES = [
    "Appearance", "Bar & workspaces", "Desktop", "Windows & controls",
    "System & language", "Services", "Advanced", "About",
]


def check_search() -> None:
    source = INDEX.read_text(encoding="utf-8")
    entries = json.loads(source.split("var entries = ", 1)[1].strip()[:-1])
    assert len({entry["id"] for entry in entries}) == len(entries), "duplicate setting ID"
    for entry in entries:
        assert 0 <= entry["pageIndex"] < len(PAGES), entry
        assert entry["page"] == PAGES[entry["pageIndex"]], entry
        if entry["path"] == "Page":
            assert entry["label"] == entry["page"], entry
        else:
            assert not entry["path"].endswith("Config"), entry
    assert {entry["pageIndex"] for entry in entries} == set(range(len(PAGES)))
    labels = {entry["label"] for entry in entries}
    assert "Open Appearance Studio" in labels
    assert "Keyboard layout" in labels
    assert "Shell language" in labels
    assert "Screen corners" in labels
    assert "Quick sliders" not in labels
    assert "Konachan" not in labels


def check_clock() -> None:
    with tempfile.TemporaryDirectory(prefix="nyvorel-settings-ci-") as directory:
        config_home = Path(directory)
        lock_config = config_home / "hypr/hyprlock.conf"
        lock_config.parent.mkdir()
        lock_config.write_text("label {\n    text = $TIME12\n}\n# keep this line\n")
        env = dict(os.environ, XDG_CONFIG_HOME=str(config_home))

        for setting, expected in (("hh:mm", "$TIME"), ("h:mm AP", "$TIME12")):
            result = subprocess.run(
                [str(HELPER), "--format", setting], env=env,
                text=True, capture_output=True, check=True,
            )
            assert json.loads(result.stdout) == {"ok": True, "token": expected[1:]}
            content = lock_config.read_text()
            assert f"text = {expected}\n" in content
            assert "# keep this line" in content

        lock_config.write_text("label { text = ${TIME12} }\n")
        unchanged = lock_config.read_bytes()
        result = subprocess.run(
            [str(HELPER), "--format", "hh:mm"], env=env,
            text=True, capture_output=True,
        )
        assert result.returncode != 0
        assert json.loads(result.stdout)["ok"] is False
        assert lock_config.read_bytes() == unchanged


if __name__ == "__main__":
    check_search()
    check_clock()
    print("Settings routes and atomic lock-clock updates passed")
