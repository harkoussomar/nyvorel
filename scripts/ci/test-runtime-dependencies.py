#!/usr/bin/env python3
"""Real file/command probes in isolated fixtures, shared diagnostic semantics."""
from importlib.machinery import SourceFileLoader
from pathlib import Path
import sys
sys.dont_write_bytecode = True
import tempfile
import unittest
from unittest.mock import patch
import subprocess

ROOT = Path(__file__).resolve().parents[2]
bootstrap = SourceFileLoader("test_bootstrap", str(ROOT / "bin/nyvorel-bootstrap")).load_module()
doctor = SourceFileLoader("test_doctor", str(ROOT / "bin/nyvorel-doctor")).load_module()


class RuntimeDependencies(unittest.TestCase):
    def check_both(self, entry, expected):
        entry = {"id": "fixture", "arch_packages_any_of": ["fixture"], **entry}
        self.assertEqual(bootstrap.command_status(entry, "")['satisfied'], expected)
        self.assertEqual(doctor.Doctor._dependency_result(entry)['satisfied'], expected)

    def test_qml_asset_does_not_need_executable_permission(self):
        with tempfile.TemporaryDirectory() as tmp:
            asset = Path(tmp) / "qmldir"
            self.check_both({"files_all_of": [str(asset)]}, False)
            asset.write_text("module QtPositioning\n")
            asset.chmod(0o644)
            self.check_both({"files_all_of": [str(asset)]}, True)

    def test_font_provider_alternatives(self):
        with tempfile.TemporaryDirectory() as tmp:
            asset = Path(tmp) / "font.ttf"
            asset.write_bytes(b"fixture")
            self.check_both({"files_any_of": [str(asset), str(asset)+".missing"]}, True)
            self.check_both({"files_any_of": [str(asset)+".missing"]}, False)

    def test_geoclue_requires_all_runtime_components(self):
        with tempfile.TemporaryDirectory() as tmp:
            files = [Path(tmp) / name for name in ("geoclue", "agent", "geoclue.service")]
            for path in files:
                path.write_text("fixture")
            entry = {"files_all_of": list(map(str, files))}
            self.check_both(entry, True)
            files[1].unlink()
            self.check_both(entry, False)
            files[1].mkdir()
            self.check_both(entry, False)

    def test_ambiguous_or_relative_selectors_are_rejected(self):
        for entry in ({"files_all_of": ["relative"]},
                      {"files_all_of": ["/usr/../tmp/file"]},
                      {"files_all_of": ["/file"], "commands_any_of": ["true"]}):
            with self.assertRaises(bootstrap.BootstrapError):
                bootstrap.runtime_selector(entry)

    def test_color_runtime_does_not_borrow_main_home_prerequisites(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            instance = doctor.Doctor(home, deep=False, session_checks=False,
                                     dependency_checks=True, strict=False)
            instance.check_appearance_runtime()
            self.assertEqual(instance.checks[-1].status, "FAIL")
            self.assertIn("Missing Matugen", instance.checks[-1].detail)
            self.assertIn("Missing color Python", instance.checks[-1].detail)
            templates = home / '.config/matugen'
            templates.mkdir(parents=True)
            (templates / 'config.toml').write_text('[templates.colors]\ninput_path="colors.json"\n')
            (templates / 'colors.json').write_text('{}')
            interpreter = home / '.local/state/quickshell/.venv/bin/python'
            interpreter.parent.mkdir(parents=True)
            interpreter.write_text('fixture')
            interpreter.chmod(0o755)
            with patch.object(doctor.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '', '')):
                instance.check_appearance_runtime()
                self.assertEqual(instance.checks[-1].status, 'PASS')
                (templates / 'colors.json').unlink()
                instance.check_appearance_runtime()
                self.assertEqual(instance.checks[-1].status, 'FAIL')
                self.assertIn('Missing Matugen template', instance.checks[-1].detail)
            with patch.object(doctor.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'ModuleNotFoundError')):
                instance.check_appearance_runtime()
                self.assertIn('modules unavailable', instance.checks[-1].detail)


if __name__ == "__main__":
    unittest.main()
