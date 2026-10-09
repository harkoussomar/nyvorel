#!/usr/bin/env python3
"""Isolated appearance regressions; never connect to the running desktop.

The subprocess-chain test substitutes external generators. Controller tests
inject failures to verify recovery, not visual rendering or Matugen quality.
"""
import importlib.util
import json
import os
from pathlib import Path
import sys
sys.dont_write_bytecode = True
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


class AppearanceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="nyvorel appearance ")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.config = self.home / "config space"
        self.state = self.home / "state space"
        self.cache = self.home / "cache space"
        self.shell = self.config / "quickshell/nyvorel"
        self.generated = self.state / "quickshell/user/generated"
        self.generated.mkdir(parents=True)
        shutil.copytree(ROOT / "quickshell/scripts/colors", self.shell / "scripts/colors")
        (self.config / "nyvorel").mkdir(parents=True)
        (self.config / "nyvorel/config.json").write_text(json.dumps({
            "appearance": {"wallpaperTheming": {"enableTerminal": False}},
        }))
        self.env = {
            **os.environ, "HOME": str(self.home),
            "XDG_CONFIG_HOME": str(self.config),
            "XDG_STATE_HOME": str(self.state),
            "XDG_CACHE_HOME": str(self.cache),
            "DBUS_SESSION_BUS_ADDRESS": "unix:path=/nonexistent",
            "HYPRLAND_INSTANCE_SIGNATURE": "",
            "WAYLAND_DISPLAY": "",
            "NYVOREL_APPEARANCE_STUDIO_MANAGED": "1",
            "NYVOREL_APPEARANCE_STUDIO_SKIP_TERMINAL": "1",
            "NYVOREL_APPEARANCE_STUDIO_SKIP_GSETTINGS": "1",
        }

    def run_script(self, name, *args):
        return subprocess.run(
            ["bash", str(self.shell / "scripts/colors" / name), *args],
            env=self.env, text=True, capture_output=True, timeout=15,
        )

    def test_applycolor_uses_nyvorel_and_xdg_paths_with_spaces(self):
        (self.generated / "material_colors.scss").write_text("$primary: #123456;\n")
        proc = self.run_script("applycolor.sh")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stderr, "")
        self.assertFalse((self.config / "quickshell/ii").exists())

    def test_missing_palette_is_failure(self):
        proc = self.run_script("applycolor.sh")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("Missing generated terminal palette", proc.stderr)

    def test_unchanged_controller_writes_do_not_trigger_watchers(self):
        module = self.controller()
        path = module.NYVOREL_CONFIG
        data = {"appearance": {"palette": {"type": "scheme-tonal-spot"}}}
        module._write_json(path, data)
        before = path.stat().st_mtime_ns
        module._write_json(path, data)
        self.assertEqual(path.stat().st_mtime_ns, before)
        module._restore_files({str(path): path.read_bytes()})
        self.assertEqual(path.stat().st_mtime_ns, before)

    def test_transaction_refuses_symlinked_personal_config(self):
        module = self.controller()
        personal = self.home / "personal rules"
        personal.write_bytes(b"private data\n")
        rules = module.HYPR_CUSTOM_RULES
        rules.parent.mkdir(parents=True, exist_ok=True)
        rules.symlink_to(personal)
        with self.assertRaisesRegex(RuntimeError, "symlink"):
            module._transaction_snapshot()
        with self.assertRaisesRegex(RuntimeError, "symlink"):
            module._restore_files({str(rules): b"overwritten\n"})
        self.assertEqual(personal.read_bytes(), b"private data\n")

    def prepare_managed_switchwall(self):
        if not shutil.which("jq"):
            self.skipTest("jq is required for the shell-chain fixture")
        commands = self.home / "commands"
        commands.mkdir()
        # All session interfaces are stubs; real Bash, jq and applycolor run.
        stubs = {
            "hyprctl": '#!/bin/sh\ncase "$1" in\nmonitors) echo \'[{"focused":true,"scale":1,"x":0,"y":0,"height":720,"width":1280}]\';;\ncursorpos) echo \'{"x":1,"y":1}\';;\nesac\n',
            "matugen": "#!/bin/sh\nexit 0\n",
            "bc": "#!/bin/sh\necho 0\n",
        }
        for name, body in stubs.items():
            target = commands / name
            target.write_text(body)
            target.chmod(0o755)
        venv = self.home / "venv"
        (venv / "bin").mkdir(parents=True)
        (venv / "bin/python").symlink_to(sys.executable)
        (self.shell / "scripts/colors/generate_colors_material.py").write_text(
            'print("$primary: #123456;")\n'
        )
        self.env.update(PATH=f"{commands}:{os.environ['PATH']}", NYVOREL_VIRTUAL_ENV=str(venv))

    def test_managed_switchwall_reaches_applycolor(self):
        self.prepare_managed_switchwall()
        proc = self.run_script("switchwall.sh", "--noswitch", "--mode", "dark",
                               "--type", "scheme-tonal-spot", "--color", "#123456")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual((self.generated / "material_colors.scss").read_text(), "$primary: #123456;\n")

    def test_missing_color_python_fails_without_evaluating_env(self):
        self.prepare_managed_switchwall()
        marker = self.home / "unexpected execution"
        self.env["NYVOREL_VIRTUAL_ENV"] = f"$(touch '{marker}')"
        proc = self.run_script("switchwall.sh", "--noswitch", "--mode", "dark",
                               "--type", "scheme-tonal-spot", "--color", "#123456")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("Nyvorel color Python environment is missing", proc.stderr)
        self.assertFalse(marker.exists())

    def controller(self):
        with patch.dict(os.environ, self.env):
            spec = importlib.util.spec_from_file_location(
                "appearance_test", ROOT / "quickshell/scripts/appearance-studio/appearance_studio.py"
            )
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
        for name in ("_gsettings_snapshot", "_restore_gsettings", "_sync_glass_runtime_for_cfg",
                     "_sync_hyprland_window_radius", "_launch_preview_watchdog", "_apply_wallpaper_runtime"):
            mock = patch.object(module, name, return_value={})
            mock.start()
            self.addCleanup(mock.stop)
        module._load_state()
        module._reconcile_state_before_mutation(module._load_state())
        return module

    def test_failed_apply_restores_files_and_absence(self):
        module = self.controller()
        baseline = module._capture_files(module._all_transaction_files())

        def fail(*args, **kwargs):
            module.COLORS_JSON.write_text('{"damaged": true}')
            module.MATERIAL_SCSS.write_text("partial output")
            raise RuntimeError("injected generation failure")

        with patch.object(module, "_run_switchwall", side_effect=fail):
            with self.assertRaisesRegex(RuntimeError, "injected generation failure"):
                module.apply_theme(source="preset", preset="midnight", mode="dark", scheme="auto")
        self.assertEqual(module._capture_files(module._all_transaction_files()), baseline)

    def test_failed_editor_integration_restores_insiders_settings(self):
        module = self.controller()
        settings = self.config / "Code - Insiders/User/settings.json"
        settings.parent.mkdir(parents=True)
        original = b'{"editor.fontSize": 14}\n'
        settings.write_bytes(original)
        script = self.home / "failed editor integration.sh"
        script.write_text(
            '#!/bin/sh\n'
            f'printf "%s" damaged > "{settings}"\n'
            'exit 1\n'
        )
        script.chmod(0o755)
        with patch.object(module, "EDITOR_COLOR_SCRIPT", script):
            warnings = module._run_post_commit_integrations(
                {"terminal": False, "editors": True, "qt": False},
                resolved_scheme="scheme-tonal-spot",
            )
        self.assertEqual(settings.read_bytes(), original)
        self.assertEqual(len(warnings), 1)
        self.assertIn("Editor accents", warnings[0])

    def test_preview_reverts_compositor_and_terminal_files(self):
        module = self.controller()
        rules = module.HYPR_CUSTOM_RULES
        kitty = module.KITTY_CONFIG
        theme = module.TERMINAL_RUNTIME_FILES[0]
        originals = (
            (rules, b"personal rules\n"),
            (kitty, b"personal kitty\n"),
            (theme, b"personal terminal theme\n"),
        )
        for path, content in originals:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
        module._prepare_preview_snapshot(module._load_state())
        module._write_json(module.NYVOREL_CONFIG, {
            "appearance": {"interfaceStyle": "fluid", "transparency": {"enable": True}}
        })
        rules.write_bytes(b"partial glass rules\n")
        kitty.write_bytes(b"partial opacity\n")
        theme.write_bytes(b"partial terminal theme\n")
        def resync(*args, **kwargs):
            rules.write_bytes(b"personal rules\n\n")
            kitty.write_bytes(b"normalized kitty\n")
            theme.write_bytes(b"normalized terminal theme\n")
            return []
        with patch.object(module, "_sync_glass_runtime_for_cfg", side_effect=resync), \
             patch.object(module, "_run_optional_command", return_value=None) as reload:
            module._restore_preview_runtime(remove=True)
        reload.assert_called_once_with(["hyprctl", "reload"], timeout=8)
        for path, content in originals:
            self.assertEqual(path.read_bytes(), content)
        self.assertFalse(module.PREVIEW_DIR.exists())

    def test_palette_only_preview_does_not_reload_interface_runtime(self):
        module = self.controller()
        resolved = {
            "source": "preset", "mode": "dark", "scheme": "scheme-tonal-spot",
            "resolvedScheme": "scheme-tonal-spot", "preset": "midnight",
            "seed": "#5368b7", "wallpaper": "", "sourceImage": "",
            "ui": {}, "baseMode": "dark", "hybridBase": {}, "intelligence": {},
        }
        with patch.object(module, "_resolve_request", return_value=resolved), \
             patch.object(module, "_generate_palette", return_value={"background": "#101010", "primary": "#5368b7"}), \
             patch.object(module, "_sync_glass_runtime_for_cfg") as sync:
            self.assertTrue(module.apply_theme(source="preset", preset="midnight", mode="dark", scheme="auto", preview=True)["ok"])
            self.assertTrue(module.revert_preview()["ok"])
        sync.assert_not_called()

    def test_each_interface_profile_and_failed_profile_rollback(self):
        module = self.controller()
        for profile in ("default", "inlay", "prism", "fluid"):
            with self.subTest(profile=profile):
                result = module.apply_ui_profile(profile)
                self.assertTrue(result["ok"])
                self.assertEqual(module._load_state()["active"]["uiProfile"], profile)
        baseline = module._capture_files(module._all_transaction_files())
        with patch.object(module, "_sync_hyprland_window_radius", side_effect=RuntimeError("radius failure")):
            with self.assertRaisesRegex(RuntimeError, "radius failure"):
                module.apply_ui_profile("default")
        self.assertEqual(module._capture_files(module._all_transaction_files()), baseline)


if __name__ == "__main__":
    unittest.main()
