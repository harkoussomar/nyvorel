#!/usr/bin/env python3
"""Verify crash-safe preview timeout scheduling without starting a timer."""

import importlib.util
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[3] / "quickshell/scripts/appearance-studio/appearance_studio.py"
spec = importlib.util.spec_from_file_location("appearance_studio_legacy", SOURCE)
controller = importlib.util.module_from_spec(spec)
spec.loader.exec_module(controller)


def test_success():
    with patch.object(controller.shutil, "which", return_value="/usr/bin/systemd-run"), \
         patch.object(controller.subprocess, "run", return_value=SimpleNamespace(returncode=0)) as run, \
         patch.object(controller.subprocess, "Popen") as spawn:
        controller._launch_preview_watchdog("token123", 3)
        args = run.call_args.args[0]
        assert "--on-active=15s" in args
        assert any(arg.startswith("--unit=nyvorel-appearance-preview-token123-3-") for arg in args)
        assert args[-5:] == ["preview-watchdog", "--token", "token123", "--revision", "3"]
        assert "appearance-studio" in args[-6]
        spawn.assert_not_called()


def test_two_independent_timers():
    with patch.object(controller.shutil, "which", return_value="/usr/bin/systemd-run"), \
         patch.object(controller.subprocess, "run", return_value=SimpleNamespace(returncode=0)) as run, \
         patch.object(controller.subprocess, "Popen") as spawn:
        controller._launch_preview_watchdog("token123", 3)
        controller._launch_preview_watchdog("token123", 3)
        units = [next(arg for arg in call.args[0] if arg.startswith("--unit="))
                 for call in run.call_args_list]
        assert len(units) == 2 and units[0] != units[1]
        spawn.assert_not_called()


def test_fallback():
    for outcome in (SimpleNamespace(returncode=1), OSError("manager unavailable")):
        with patch.object(controller.shutil, "which", return_value="/usr/bin/systemd-run"), \
             patch.object(controller.subprocess, "run", side_effect=outcome if isinstance(outcome, Exception) else None,
                          return_value=None if isinstance(outcome, Exception) else outcome), \
             patch.object(controller.subprocess, "Popen") as spawn:
            controller._launch_preview_watchdog("token123", 3)
            assert spawn.call_count == 1
            assert spawn.call_args.kwargs["start_new_session"] is True


if __name__ == "__main__":
    test_success()
    test_two_independent_timers()
    test_fallback()
    print("Preview watchdog timer and detached fallback: passed")
