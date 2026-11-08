#!/usr/bin/env python3
"""Exercise Appearance Studio with Arch package-owned runtime helpers."""

from pathlib import Path
import json
import shutil
import tempfile

from native_flow import PROJECT, fixture, invoke


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
        # Fresh Arch installs do not include the optional ImageMagick package.
        # The packaged backend must still apply a regular PNG wallpaper.
        matugen = shutil.which("matugen")
        if matugen is None:
            raise RuntimeError("matugen is required for the package runtime test")
        (root / "bin/matugen").symlink_to(matugen)
        no_magick_env = dict(env, PATH=str(root / "bin"))
        wallpaper = PROJECT / "quickshell/assets/images/default_wallpaper.png"
        applied = invoke("rust", ["apply", "--source", "wallpaper",
                                  "--wallpaper", str(wallpaper), "--mode", "dark",
                                  "--scheme", "auto"], no_magick_env)
        assert applied["ok"] is True
        assert applied["active"]["source"] == "wallpaper"
    print("PASS package-owned Appearance Studio helpers and wallpaper apply without ImageMagick")


if __name__ == "__main__":
    main()
