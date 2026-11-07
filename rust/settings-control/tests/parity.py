#!/usr/bin/env python3
"""Compare the legacy Python controller and the Rust CLI in disposable profiles.

Run after `cargo build`: python3 tests/parity.py [path-to-rust-binary]
"""

import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

PYTHON = Path(__file__).resolve().with_name("legacy_settings_control.py")
RUST = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "target/debug/nyvorel-settings-control"
FIELDS = (
    "config_valid", "favorite_count", "history_count", "can_undo",
    "hyprland_ok", "hyprland_version", "hyprland_config_errors_available",
    "hyprland_config_error_count", "hyprland_legacy_conf", "warning_count",
    "diagnostics_ok", "critical_count", "shell_running", "settings_running",
)


def write_config(profile, value):
    path = profile / ".config/nyvorel/config.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


def run(binary, profile, command, *args):
    env = profile_env(profile)
    argv = [sys.executable, str(binary)] if binary == PYTHON else [str(binary)]
    result = subprocess.run([*argv, command, *args], env=env, capture_output=True, text=True, timeout=15, check=True)
    assert result.stderr == "", result.stderr
    return json.loads(result.stdout)


def profile_env(profile):
    env = os.environ.copy()
    env["HOME"] = str(profile)
    env["XDG_CONFIG_HOME"] = str(profile / ".config")
    env["XDG_RUNTIME_DIR"] = str(profile / "runtime")
    env["PATH"] = f"{profile.parent / 'fake-bin'}:/usr/bin:/bin"
    env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
    env.pop("HYPRLAND_CONFIG", None)
    return env


def comparable(value):
    if isinstance(value, list):
        return [comparable(item) for item in value]
    if isinstance(value, dict):
        return {key: comparable(item) for key, item in value.items() if key != "timestamp"}
    if isinstance(value, str):
        return re.sub(r"\d{8}-\d{6}(?:-\d+)?", "<stamp>", value)
    return value


def compare(command, rust, python):
    for field in FIELDS:
        assert rust[field] == python[field], (command, field, rust[field], python[field])
    for field in ("favorites", "history"):
        if field in python:
            assert comparable(rust[field]) == comparable(python[field]), (command, field)
    if "error" in python:
        assert rust.get("error") == python["error"], (command, "error")
    if "message" in python:
        assert comparable(rust.get("message")) == comparable(python["message"]), (command, "message", rust.get("message"), python["message"])


def main():
    assert RUST.exists(), f"Build the Rust binary first: {RUST}"
    with tempfile.TemporaryDirectory(prefix="nyvorel-settings-parity-") as folder:
        base = Path(folder)
        fake_bin = base / "fake-bin"
        fake_bin.mkdir()
        hyprctl = fake_bin / "hyprctl"
        hyprctl.write_text("#!/bin/sh\ncase \"$1\" in version) echo 'Hyprland 0.56.1';; configerrors) exit 0;; *) exit 1;; esac\n")
        hyprctl.chmod(0o755)
        profiles = {"rust": base / "rust", "python": base / "python"}
        for profile in profiles.values():
            write_config(profile, {"bar": {"height": 36}, "unknown": ["keep", 1]})

        def step(command, *args):
            outputs = {name: run(RUST if name == "rust" else PYTHON, profile, command, *args)
                       for name, profile in profiles.items()}
            compare(command, outputs["rust"], outputs["python"])

        step("status")
        step("snapshot")
        step("toggle-favorite", "bar.height")
        step("favorites")
        step("toggle-favorite", "bar.height")
        step("toggle-favorite", "unknown")
        for profile in profiles.values():
            write_config(profile, {"bar": {"height": 40, "visible": True}, "unknown": ["keep", 1]})
        step("snapshot")
        step("history")
        step("backup")
        step("undo")
        step("restore-latest")
        for profile in profiles.values():
            assert json.loads((profile / ".config/nyvorel/config.json").read_text()) == {"bar": {"height": 40, "visible": True}, "unknown": ["keep", 1]}
            write_config(profile, {"bar": {"height": 42}})
        step("snapshot")
        for profile in profiles.values():
            (profile / ".config/nyvorel/config.json").write_text("{invalid", encoding="utf-8")
        step("status")
        step("snapshot")
        for profile in profiles.values():
            (profile / ".config/nyvorel/config.json").unlink()
        step("status")
        step("snapshot")

        # A corrupt state file must fall back to empty state without touching config.
        for profile in profiles.values():
            write_config(profile, {"bar": {"height": 50}})
            state_file = profile / ".local/state/nyvorel/settings-control/state.json"
            state_file.write_text("{broken", encoding="utf-8")
        step("status")
        for profile in profiles.values():
            write_config(profile, ["wrong root type"])
        step("status")
        for profile in profiles.values():
            write_config(profile, {"bar": {"height": 50}})
            (profile / ".config/nyvorel/config.json").chmod(0o000)
        try:
            step("status")
        finally:
            for profile in profiles.values():
                (profile / ".config/nyvorel/config.json").chmod(0o600)

        # No-history and no-backup branches in fresh profiles.
        fresh = {name: base / f"{name}-fresh" for name in profiles}
        for profile in fresh.values():
            write_config(profile, {"fresh": True})
        for command in ("undo", "restore-latest"):
            outputs = {name: run(RUST if name == "rust" else PYTHON, profile, command)
                       for name, profile in fresh.items()}
            compare(command, outputs["rust"], outputs["python"])

        for profile in fresh.values():
            backups = profile / ".local/state/nyvorel/settings-control/backups"
            backups.mkdir(parents=True)
            (backups / "invalid.json").write_text("not json", encoding="utf-8")
        outputs = {name: run(RUST if name == "rust" else PYTHON, profile, "restore-latest")
                   for name, profile in fresh.items()}
        compare("restore-latest-invalid", outputs["rust"], outputs["python"])

        hyprctl.write_text("#!/bin/sh\nexit 1\n")
        step("status")

        # Concurrent Rust actions must retain all favorites. The Python controller
        # has no transaction lock, so this intentionally tests only Rust.
        rust_profile = base / "concurrent"
        write_config(rust_profile, {"fresh": True})
        children = [subprocess.Popen([str(RUST), "toggle-favorite", f"item-{index}"],
                                     env=profile_env(rust_profile), stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE, text=True)
                    for index in range(20)]
        for child in children:
            stdout, stderr = child.communicate(timeout=20)
            assert child.returncode == 0 and stderr == "", (child.returncode, stderr)
            assert "error" not in json.loads(stdout), stdout
        favorites = run(RUST, rust_profile, "favorites")["favorites"]
        assert len(favorites) == 20 and set(favorites) == {f"item-{index}" for index in range(20)}

        print("Python/Rust parity: 23 command scenarios passed; Rust concurrent favorites: 20/20 retained")


if __name__ == "__main__":
    main()
