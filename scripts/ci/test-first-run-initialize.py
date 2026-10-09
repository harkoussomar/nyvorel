#!/usr/bin/env python3
"""Check first-run recovery without touching a real desktop or network."""
from importlib.machinery import SourceFileLoader
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
first_run = SourceFileLoader("nyvorel_first_run_test", str(ROOT / "bin/nyvorel-first-run")).load_module()


class FirstRunTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="nyvorel-first-run-test-")
        self.addCleanup(temp.cleanup)
        self.home = Path(temp.name)
        self.paths = first_run.target_paths(self.home)
        self.existing = self.paths["hyprland"]
        self.existing.parent.mkdir(parents=True)
        self.existing.write_bytes(b"original compositor colors\n")
        self.outputs = {key: (key + " generated\n").encode() for key in self.paths}

    def test_initialization_backs_up_existing_color_and_installs_outputs(self):
        backup = first_run.initialize(self.home, self.paths, self.outputs)
        manifest = json.loads((backup / "manifest.json").read_text())
        self.assertEqual(manifest["status"], "installed")
        original = manifest["files"]["hyprland"]
        self.assertEqual((backup / original["backup"]).read_bytes(), b"original compositor colors\n")
        for key, path in self.paths.items():
            self.assertEqual(path.read_bytes(), self.outputs[key])

    def test_verified_rollback_restores_prior_bytes_and_absence(self):
        backup = first_run.initialize(self.home, self.paths, self.outputs)
        first_run.rollback(self.home, backup)
        self.assertEqual(self.existing.read_bytes(), b"original compositor colors\n")
        for key, path in self.paths.items():
            if key != "hyprland":
                self.assertFalse(path.exists(), key)
        self.assertEqual(json.loads((backup / "manifest.json").read_text())["status"], "restored")

    def test_rollback_refuses_changed_output_without_partial_restore(self):
        backup = first_run.initialize(self.home, self.paths, self.outputs)
        self.paths["gtk3"].write_bytes(b"changed by user\n")
        with self.assertRaisesRegex(RuntimeError, "changed after initialization"):
            first_run.rollback(self.home, backup)
        self.assertEqual(self.existing.read_bytes(), self.outputs["hyprland"])
        self.assertEqual(self.paths["gtk3"].read_bytes(), b"changed by user\n")

    def test_mid_transaction_failure_restores_bytes_and_prior_absence(self):
        original_write = first_run.atomic_write
        count = 0

        def fail_once(path, content, mode):
            nonlocal count
            count += 1
            if count == 4:
                raise RuntimeError("injected disk failure")
            return original_write(path, content, mode)

        with patch.object(first_run, "atomic_write", side_effect=fail_once):
            with self.assertRaisesRegex(RuntimeError, "injected disk failure"):
                first_run.initialize(self.home, self.paths, self.outputs)
        self.assertEqual(self.existing.read_bytes(), b"original compositor colors\n")
        for key, path in self.paths.items():
            if key != "hyprland":
                self.assertFalse(path.exists(), key)

    def test_symlinked_target_is_refused_without_following_it(self):
        personal = self.home / "personal"
        personal.write_bytes(b"private\n")
        self.existing.unlink()
        self.existing.symlink_to(personal)
        with self.assertRaisesRegex(RuntimeError, "non-regular"):
            first_run.initialize(self.home, self.paths, self.outputs)
        self.assertEqual(personal.read_bytes(), b"private\n")

    def test_symlinked_parent_is_refused_without_writing_outside_home(self):
        outside = self.home / "outside"
        outside.mkdir()
        config = self.home / ".config"
        shutil.rmtree(config)
        config.symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(RuntimeError, "symlinked first-run parent"):
            first_run.initialize(self.home, self.paths, self.outputs)
        self.assertEqual(list(outside.rglob("*")), [])


if __name__ == "__main__":
    unittest.main()
