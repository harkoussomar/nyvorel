#!/usr/bin/env python3
"""Export/check the Rust UI catalog from the preserved Python controller."""

import argparse
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT.parents[1] / "quickshell/scripts/appearance-studio/appearance_studio.py"
CATALOG = ROOT / "src/catalog.json"


def export():
    spec = importlib.util.spec_from_file_location("appearance_studio_legacy", SOURCE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return {
        "presets": module.PRESETS,
        "schemes": [{"id": key, "name": name} for key, name in module.SCHEMES],
        "modes": [{"id": key, "name": name} for key, name in module.MODES],
        "uiProfiles": [
            {"id": key, "name": profile["name"],
             "description": profile["description"], "patch": profile["patch"]}
            for key, profile in module.UI_PROFILES.items()
        ],
        "radiusDefaults": module.RADIUS_DEFAULTS,
        "radiusRoles": list(module.RADIUS_ROLES),
        "snapshotKeys": list(module._config_snapshot()),
        "legacyAliases": module.LEGACY_UI_PROFILE_ALIASES,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help="update src/catalog.json")
    args = parser.parse_args()
    expected = export()
    if args.write:
        CATALOG.write_text(json.dumps(expected, ensure_ascii=False, indent=2) + "\n")
        print("Catalog updated")
    elif json.loads(CATALOG.read_text()) != expected:
        raise SystemExit("Catalog differs from the preserved controller; run tools/catalog.py --write")
    else:
        print("Catalog matches the preserved controller")
