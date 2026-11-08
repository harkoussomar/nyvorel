#!/usr/bin/env python3
"""Exercise Appearance Studio with Arch package-owned runtime helpers."""

from pathlib import Path
import json
import tempfile

from native_flow import fixture, invoke


def main():
    with tempfile.TemporaryDirectory(prefix="nyvorel-package-appearance-") as directory:
        root = Path(directory)
        env = fixture(root)
        package_root = root / "package-helpers"
        package_root.mkdir()
        user_helpers = root / "home/.local/bin"
        for name in ("nyvorel-glass-runtime", "nyvorel-fluid-runtime"):
            (user_helpers / name).rename(package_root / name)
        env["NYVOREL_PACKAGE_HELPER_ROOT"] = str(package_root)
        ui = {
            "appearance.interfaceStyle": "fluid",
            "appearance.transparency.enable": True,
            "appearance.transparency.automatic": False,
            "appearance.transparency.backgroundTransparency": 0.4,
            "appearance.transparency.contentTransparency": 0.8,
        }
        invoke("rust", ["apply", "--source", "preset", "--preset", "ocean",
                        "--mode", "dark", "--ui-json", json.dumps(ui)], env)
        config = json.loads((root / "home/.config/nyvorel/config.json").read_text())
        assert config["appearance"]["interfaceStyle"] == "fluid"
        assert config["appearance"]["transparency"]["backgroundTransparency"] == 0.4
    print("PASS package-owned Appearance Studio runtime helpers")


if __name__ == "__main__":
    main()
