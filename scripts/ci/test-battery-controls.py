#!/usr/bin/env python3
"""Battery bridge regression tests with isolated sysfs/helper fixtures."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('battery_control', ROOT / 'quickshell/scripts/battery/control.py')
control = importlib.util.module_from_spec(spec)
spec.loader.exec_module(control)


class BatteryControls(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.modern = (root / 'nyvorel-helper', root / 'nyvorel-config')
        self.legacy = (root / 'ii-helper', root / 'ii-config')
        self.threshold = root / 'threshold'
        self.threshold.write_text('100\n')
        for name, value in [('BACKENDS', (self.modern, self.legacy)), ('THRESHOLD', self.threshold)]:
            context = patch.object(control, name, value)
            context.start()
            self.addCleanup(context.stop)

    def install(self, pair, saved='80\n'):
        pair[0].write_text('#!/bin/sh\n')
        pair[0].chmod(0o755)
        if saved is not None:
            pair[1].write_text(saved)

    def test_legacy_installation_is_supported(self):
        self.install(self.legacy)
        self.assertEqual(control.backend(), self.legacy)
        self.assertEqual(control.status()['persistent'], 80)
        self.assertTrue(control.status()['available'])

    def test_modern_backend_and_config_take_precedence_together(self):
        self.install(self.legacy, '60\n')
        self.install(self.modern, '90\n')
        self.assertEqual(control.backend(), self.modern)
        self.assertEqual(control.status()['persistent'], 90)

    def test_absent_backend_is_unavailable_not_zero_percent(self):
        state = control.status()
        self.assertFalse(state['available'])
        self.assertEqual(state['persistent'], 100)
        self.assertIn('not installed', state['message'])

    def test_missing_empty_or_invalid_config_never_enables_protection(self):
        for text in (None, '', '\n', '0', '-1', '101', 'garbage', '80.5', '55'):
            with self.subTest(text=text):
                self.install(self.legacy, text)
                self.assertEqual(control.status()['persistent'], 100)

    def test_unreadable_or_invalid_hardware_is_unavailable(self):
        self.install(self.legacy)
        for text in ('', '0', '-1', '101', 'garbage'):
            self.threshold.write_text(text)
            self.assertFalse(control.status()['available'])
            self.assertEqual(control.status()['current'], -1)
        self.threshold.unlink()
        self.assertFalse(control.status()['available'])

    def test_invalid_action_never_runs_sudo(self):
        self.install(self.legacy)
        with patch.object(control.subprocess, 'run') as run:
            for args in ([], ['set', '0'], ['set', '80', 'extra'], ['apply'], ['once', 'extra']):
                with self.assertRaises(ValueError):
                    control.action(args)
            run.assert_not_called()

    def test_all_limits_are_written_and_read_back(self):
        self.install(self.legacy)
        def apply(command, **kwargs):
            self.assertEqual(command[:3], ['/usr/bin/sudo', '-n', str(self.legacy[0])])
            self.assertEqual(kwargs['timeout'], 15)
            value = command[-1]
            self.threshold.write_text(value)
            self.legacy[1].write_text(value)
            return subprocess.CompletedProcess(command, 0, '', '')
        with patch.object(control.subprocess, 'run', side_effect=apply):
            for value in control.LIMITS:
                state = control.action(['set', str(value)])
                self.assertEqual((state['current'], state['persistent']), (value, value))

    def test_full_charge_override_preserves_saved_limit(self):
        self.install(self.legacy)
        self.threshold.write_text('80')
        def apply(command, **kwargs):
            self.assertEqual(command[-1], 'once')
            self.threshold.write_text('100')
            return subprocess.CompletedProcess(command, 0, '', '')
        with patch.object(control.subprocess, 'run', side_effect=apply):
            state = control.action(['once'])
            self.assertEqual((state['current'], state['persistent']), (100, 80))

    def test_denied_action_is_reported(self):
        self.install(self.legacy)
        result = subprocess.CompletedProcess([], 1, '', 'sudo: a password is required')
        with patch.object(control.subprocess, 'run', return_value=result):
            with self.assertRaisesRegex(ValueError, 'password is required'):
                control.action(['set', '80'])

    def test_success_without_hardware_change_is_reported(self):
        self.install(self.legacy)
        with patch.object(control.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '', '')):
            with self.assertRaisesRegex(ValueError, 'did not match'):
                control.action(['set', '80'])


if __name__ == '__main__':
    unittest.main()
