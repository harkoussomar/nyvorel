#!/usr/bin/env python3
"""Differential contract checks against the preserved live Python backend.

All mutation checks run under temporary XDG directories. The only live call is
the read-only `status` command. This test never applies a theme or preview.
"""

import json
import importlib.util
import os
from pathlib import Path
import random
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
RUST = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "target/release/nyvorel-appearance-studio"
PYTHON = ROOT.parents[1] / "quickshell/scripts/appearance-studio/appearance_studio.py"
HOME = Path.home()


def run(command, args, env=None):
    result = subprocess.run(command + args, env=env, capture_output=True, text=True, timeout=30)
    if not result.stdout:
        raise AssertionError(f"No JSON from {command}: {result.stderr}")
    return result.returncode, json.loads(result.stdout)


def compare(args, env=None):
    python = run(["/usr/bin/python3", str(PYTHON)], args, env)
    rust = run([str(RUST)], args, env)
    if rust != python:
        raise AssertionError(f"Contract mismatch for {args}:\nPython: {python}\nRust: {rust}")


def normalize_generated(value):
    if isinstance(value, dict):
        result = {key: normalize_generated(item) for key, item in value.items()}
        if {"id", "timestamp", "fingerprint", "active", "ui"} <= result.keys():
            result["id"] = "<generated>"
            result["timestamp"] = "<generated>"
        return result
    if isinstance(value, (list, tuple)):
        return [normalize_generated(item) for item in value]
    return value


def approximately_equal(left, right):
    if isinstance(left, (int, float)) and not isinstance(left, bool) and isinstance(right, (int, float)) and not isinstance(right, bool):
        return abs(left - right) <= 1e-10
    if isinstance(left, dict) and isinstance(right, dict):
        return left.keys() == right.keys() and all(approximately_equal(left[key], right[key]) for key in left)
    if isinstance(left, list) and isinstance(right, list):
        return len(left) == len(right) and all(approximately_equal(a, b) for a, b in zip(left, right))
    return left == right


def prepare_tree(root):
    config = root / "config/nyvorel"
    generated = root / "state/quickshell/user/generated"
    config.mkdir(parents=True)
    generated.mkdir(parents=True)
    for source, target in [
        (HOME / ".config/nyvorel/config.json", config / "config.json"),
        (HOME / ".config/nyvorel/appearance-studio.json", config / "appearance-studio.json"),
        (HOME / ".local/state/quickshell/user/generated/colors.json", generated / "colors.json"),
    ]:
        shutil.copy2(source, target)
    return config


def isolated_env(root):
    return dict(os.environ,
                XDG_CONFIG_HOME=str(root / "config"),
                XDG_STATE_HOME=str(root / "state"),
                XDG_CACHE_HOME=str(root / "cache"),
                NYVOREL_APPEARANCE_LEGACY=str(PYTHON))


def main():
    spec = importlib.util.spec_from_file_location("appearance_legacy", PYTHON)
    legacy_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(legacy_module)
    sample_colors = json.loads((HOME / ".local/state/quickshell/user/generated/colors.json").read_text())
    live_config = json.loads((HOME / ".config/nyvorel/config.json").read_text())
    for draft in (
        {"source": "preset", "preset": "midnight", "scheme": "auto", "mode": "dark", "ui": {}},
        {"source": "custom", "seed": "#ad4279", "scheme": "scheme-tonal-spot", "mode": "dim", "ui": {}},
        {"source": "custom", "seed": "ii4:#AD4279|#22BBCC|#7744AA|#777777", "scheme": "auto", "mode": "oled", "ui": {}},
    ):
        expected = legacy_module._resolve_request(dict(draft), live_config, preview=True)
        resolved = subprocess.run([str(RUST), "__resolve"], input=json.dumps(draft), capture_output=True, text=True, timeout=10, check=True)
        got = json.loads(resolved.stdout)
        got.pop("customPalette", None)
        if got != expected:
            raise AssertionError(f"Draft request resolution mismatch for {draft}")
    rng = random.Random(82072)
    color_roles = list(sample_colors)
    palettes = [sample_colors] + [
        {role: f"#{rng.randrange(1 << 24):06x}" for role in color_roles}
        for _ in range(20)
    ]
    for colors in palettes:
        for mode in ("light", "dark", "dim", "oled", "high-contrast"):
            result = subprocess.run(
                [str(RUST), "__special-mode", mode],
                input=json.dumps(colors), capture_output=True, text=True, timeout=10,
            )
            if result.returncode or json.loads(result.stdout) != legacy_module._apply_special_mode_colors(colors, mode):
                raise AssertionError(f"Special-mode palette mismatch for {mode}: {result.stdout}")
    with tempfile.TemporaryDirectory(prefix="nyvorel-profile-parity-") as profile_folder:
        image = Path(profile_folder) / "sample.ppm"
        pixels = ["150 40 55", "30 110 175", "230 175 85", "40 60 55"]
        image.write_text("P3\n8 8\n255\n" + "\n".join(pixels[(x // 4) + 2 * (y // 4)] for y in range(8) for x in range(8)) + "\n")
        python_profile = run(["python3", str(PYTHON.parent / "wallpaper_profile.py")], [str(image)])[1]
        rust_profile = run([str(RUST)], ["__profile", str(image)])[1]
        if not approximately_equal(python_profile, rust_profile):
            raise AssertionError("Wallpaper profile differs between Python and Rust")
        seed = python_profile["accentCandidates"][0]["hex"]
        python_score, python_metrics = legacy_module._score_real_palette(python_profile, sample_colors, seed)
        rust_score = subprocess.run(
            [str(RUST), "__score"], input=json.dumps({"profile": rust_profile, "palette": sample_colors, "seed": seed}),
            capture_output=True, text=True, timeout=10, check=True,
        )
        scored = json.loads(rust_score.stdout)
        expected = {"score": python_score, "metrics": python_metrics, "reason": legacy_module._smart_reason(python_metrics)}
        if not approximately_equal(scored, expected):
            raise AssertionError("Wallpaper palette scoring differs between Python and Rust")
        variant_env = dict(os.environ, XDG_CACHE_HOME=str(Path(profile_folder) / "cache"),
                           NYVOREL_APPEARANCE_SMART_SEEDS="1")
        variant_result = run([str(RUST)], ["__variants", str(image), "dark"], variant_env)[1]
        if len(variant_result.get("variants", [])) != 9 or variant_result["variants"][0]["id"] != "auto":
            raise AssertionError("Native wallpaper variants are incomplete")
    compare(["status"])
    with tempfile.TemporaryDirectory(prefix="nyvorel-appearance-parity-") as folder:
        root = Path(folder)
        config = prepare_tree(root)
        env = isolated_env(root)
        compare(["status"], env)

        # A fresh installation has config and generated colors, but no Studio
        # metadata yet. Status must remain read-only and match Python defaults.
        state_file = config / "appearance-studio.json"
        original_state = state_file.read_bytes()
        state_file.unlink()
        compare(["status"], env)
        if state_file.exists():
            raise AssertionError("First-run status unexpectedly wrote Studio state")
        state_file.write_bytes(original_state)

        legacy = json.loads(original_state)
        legacy.pop("activeUi", None)
        legacy["targets"].pop("qt", None)
        legacy["active"]["uiProfile"] = "mica"
        state_file.write_text(json.dumps(legacy))
        compare(["status"], env)
        state_file.write_bytes(original_state)

        state = json.loads(state_file.read_text())
        state["preview"] = {"token": "contract-test", "revision": 2, "expiresAt": 9999999999}
        state_file.write_text(json.dumps(state))
        compare(["status"], env)

        state["preview"] = None
        state_file.write_text(json.dumps(state))
        cfg_file = config / "config.json"
        cfg = json.loads(cfg_file.read_text())
        cfg.setdefault("appearance", {})["interfaceStyle"] = "mica"
        cfg_file.write_text(json.dumps(cfg))
        compare(["status"], env)

        # Check both mutation output and resulting state on separate copies.
        for args in (["clear-history"], ["favorite-remove", "missing-id"], ["revert-preview"],
                     ["favorite-add"], ["favorite-add", "--label", "Contract test"],
                     ["target", "shell", "false"], ["target", "qt", "false"],
                     ["target", "terminal", "0"]):
            copies = []
            for backend in ("python", "rust"):
                branch = root / backend
                branch_config = prepare_tree(branch)
                original = json.loads((branch_config / "appearance-studio.json").read_text())
                original["history"] = [{"id": "history-test"}]
                original["favorites"] = [{"id": "missing-id"}, {"id": "keep-id"}]
                (branch_config / "appearance-studio.json").write_text(json.dumps(original))
                branch_env = isolated_env(branch)
                command = ["/usr/bin/python3", str(PYTHON)] if backend == "python" else [str(RUST)]
                output = run(command, args, branch_env)
                after = json.loads((branch_config / "appearance-studio.json").read_text())
                after_config = json.loads((branch_config / "config.json").read_text())
                copies.append(normalize_generated((output, after, after_config)))
                shutil.rmtree(branch)
            if copies[0] != copies[1]:
                raise AssertionError(f"Mutation mismatch for {args}")

        for args in (["clear-history"], ["favorite-remove", "missing-id"]):
            copies = []
            for backend in ("python", "rust"):
                branch = root / f"first-run-{backend}"
                branch_config = prepare_tree(branch)
                (branch_config / "appearance-studio.json").unlink()
                branch_env = isolated_env(branch)
                command = ["/usr/bin/python3", str(PYTHON)] if backend == "python" else [str(RUST)]
                output = run(command, args, branch_env)
                after = json.loads((branch_config / "appearance-studio.json").read_text())
                copies.append((output, after))
                shutil.rmtree(branch)
            if copies[0] != copies[1]:
                raise AssertionError(f"First-run mutation mismatch for {args}")

        # Both user-initiated and watchdog recovery use isolated XDG trees and
        # fake runtime helpers, so neither path touches the live desktop.
        for action in (["revert-preview"], ["preview-watchdog", "--token", "contract-preview", "--revision", "1"]):
            copies = []
            for backend in ("python", "rust"):
                branch = root / f"revert-{backend}"
                branch_config = prepare_tree(branch)
                branch_env = isolated_env(branch)
                branch_env["HOME"] = str(branch)
                helper_dir = branch / ".local/bin"
                helper_dir.mkdir(parents=True)
                for helper in ("nyvorel-glass-runtime", "nyvorel-fluid-runtime"):
                    helper_path = helper_dir / helper
                    helper_path.write_text(f'#!/bin/sh\nprintf "%s %s\\n" {helper} "$1" >> "$HOME/runtime.log"\n')
                    helper_path.chmod(0o755)
                cfg_path = branch_config / "config.json"
                colors_path = branch / "state/quickshell/user/generated/colors.json"
                baseline = json.loads((branch_config / "appearance-studio.json").read_text())
                baseline["preview"] = None
                committed_cfg = cfg_path.read_bytes()
                committed_colors = colors_path.read_bytes()
                preview_dir = branch / "cache/nyvorel-appearance-studio/preview"
                (preview_dir / "files").mkdir(parents=True)
                (preview_dir / "files/000").write_bytes(committed_cfg)
                (preview_dir / "files/001").write_bytes(committed_colors)
                (preview_dir / "manifest.json").write_text(json.dumps({str(cfg_path): "000", str(colors_path): "001"}))
                (preview_dir / "state-before.json").write_text(json.dumps(baseline))
                (preview_dir / "gsettings.json").write_text("{}")
                draft_cfg = json.loads(committed_cfg)
                appearance = draft_cfg.setdefault("appearance", {})
                transparency = appearance.setdefault("transparency", {})
                transparency["enable"] = not bool(transparency.get("enable"))
                cfg_path.write_text(json.dumps(draft_cfg))
                colors_path.write_text('{"preview":"draft"}')
                current = dict(baseline)
                current["preview"] = {"token": "contract-preview", "revision": 1,
                                      "expiresAt": 0 if action[0] == "preview-watchdog" else 9999999999}
                current["history"] = [{"id": "preserve-current-history"}]
                (branch_config / "appearance-studio.json").write_text(json.dumps(current))
                command = ["/usr/bin/python3", str(PYTHON)] if backend == "python" else [str(RUST)]
                output = run(command, action, branch_env)
                after = json.loads((branch_config / "appearance-studio.json").read_text())
                after_cfg = json.loads(cfg_path.read_text())
                after_colors = colors_path.read_bytes()
                runtime_log = (branch / "runtime.log").read_text() if (branch / "runtime.log").exists() else ""
                copies.append((output, after, after_cfg, after_colors, preview_dir.exists(), runtime_log))
                shutil.rmtree(branch)
            if copies[0] != copies[1]:
                raise AssertionError(f"Preview recovery mismatch for {action}:\nPython: {copies[0]}\nRust: {copies[1]}")

        compare(["preview-watchdog", "--token", "stale-token", "--revision", "9"], env)
        compare(["variants", "--wallpaper", "/definitely/missing/wallpaper.png"], env)
    print("Appearance Studio Python/Rust parity: live status, isolated status, preview recovery, aliases, and mutations passed")


if __name__ == "__main__":
    main()
