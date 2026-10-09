#!/usr/bin/env python3
"""Exercise four style-sync services against one isolated user home."""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
STYLES = ("default", "inlay", "prism", "fluid")
SERVICES = (
    "nyvorel-btop-style-sync",
    "nyvorel-fuzzel-style-sync",
    "nyvorel-kde-app-style-sync",
    "nyvorel-zen-code-style-sync",
)


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


spec = importlib.util.spec_from_file_location(
    "appearance_contract", ROOT / "quickshell/scripts/appearance-studio/appearance_studio.py"
)
assert spec and spec.loader
contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract)

with tempfile.TemporaryDirectory(prefix="nyvorel-style-sync-") as raw:
    home = Path(raw) / "user"
    home.mkdir()
    env = os.environ.copy()
    env["HOME"] = str(home)
    env["XDG_CONFIG_HOME"] = str(home / ".config")
    env["XDG_STATE_HOME"] = str(home / ".local/state")

    colors = {name: "#5a7898" for name in contract.MATERIAL_ROLES}
    colors.update(background="#15202a", on_background="#e8f0f8", on_surface="#e8f0f8")
    write(home / ".local/state/quickshell/user/generated/colors.json", json.dumps(colors))
    write(home / ".config/btop/btop.conf", 'color_theme = "Default"\nrounded_corners = true\n')
    write(home / ".config/kdeglobals", "[General]\nColorScheme=IllogicalImpulse\n")
    write(home / ".config/Code/User/settings.json", '{\n  "workbench.colorTheme": "Nyvorel System"\n}\n')
    write(home / ".zen/profiles.ini", "[InstallNyvorel]\nDefault=ci-profile\n")

    for style in STYLES:
        write(
            home / ".config/nyvorel/config.json",
            json.dumps({"appearance": {"interfaceStyle": style}}),
        )
        for service in SERVICES:
            result = subprocess.run(
                [str(ROOT / "bin" / service)], env=env, check=False,
                capture_output=True, text=True, timeout=20,
            )
            assert result.returncode == 0, f"{service} {style}: {result.stderr or result.stdout}"

        marker = (home / ".config/btop/.nyvorel-style-managed").read_text()
        fuzzel = (home / ".config/fuzzel/nyvorel-style.ini").read_text()
        kde = (home / ".config/kdeglobals").read_text()
        css = (home / ".zen/ci-profile/chrome/nyvorel-interface-style.css").read_text()
        code = (home / ".config/Code/User/settings.json").read_text()
        assert f"interfaceStyle={style}" in marker
        assert f"interfaceStyle={style}" in fuzzel
        assert f"interfaceStyle={style}" in css
        assert (home / ".config/btop/themes/nyvorel-prism.theme").is_file()
        assert (home / ".local/share/color-schemes/IllogicalImpulsePrism.colors").is_file()
        assert (home / ".vscode/extensions/nyvorel-interface-styles-1.0.0/themes/prism-color-theme.json").is_file()
        if style == "fluid":
            assert "ColorScheme=IllogicalImpulse\n" in kde
            assert "Nyvorel System" in code
        else:
            assert f"ColorScheme=IllogicalImpulse{style.title()}" in kde
            assert f"Nyvorel {style.title()}" in code
        print(f"PASS {style}: btop, Fuzzel, KDE, Zen and Code outputs")
