#!/usr/bin/env python3
"""Verify system login provisioning against a disposable filesystem."""

from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path
import os
import subprocess
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
TEMPLATE = ROOT / "packaging/nyvorel.desktop"
loader = SourceFileLoader("graphical_login", str(TEMPLATE.with_name("nyvorel-graphical-login")))
spec = spec_from_loader(loader.name, loader)
login = module_from_spec(spec)
loader.exec_module(login)


class GraphicalLoginTest(unittest.TestCase):
    def setUp(self):
        workspace = self.enterContext(tempfile.TemporaryDirectory())
        self.root = Path(workspace)
        self.session = self.root / login.LOCAL_SESSION.relative_to("/")
        self.launcher = self.root / login.LOCAL_LAUNCHER.relative_to("/")
        self.saved_session = self.root / "var/lib/sddm/state.conf"
        self.manager = ""
        self.active = False
        self.default = "multi-user.target"
        self.fail_default = False
        self.calls = []
        self.enterContext(patch.object(login, "systemctl", self.systemctl))
        account = SimpleNamespace(pw_dir="/var/lib/sddm", pw_uid=os.getuid(), pw_gid=os.getgid())
        self.enterContext(patch.object(login.pwd, "getpwnam", return_value=account))

    def systemctl(self, *args):
        self.calls.append(args)
        if args[0] == "show" and args[1] == "display-manager.service":
            if self.manager:
                return f"LoadState=loaded\nFragmentPath=/usr/lib/systemd/system/{self.manager}"
            return "LoadState=not-found\nFragmentPath="
        if args[0] == "show" and args[1] == "sddm.service":
            return "active" if self.active else "inactive"
        if args == ("get-default",):
            return self.default
        if self.fail_default and args[0] == "set-default":
            raise subprocess.CalledProcessError(1, args)
        return ""

    def install_source(self):
        login.configure("source", TEMPLATE, self.root)

    def install_packaged_entry(self):
        desktop = self.root / login.PACKAGE_SESSION.relative_to("/")
        desktop.parent.mkdir(parents=True)
        desktop.write_bytes(TEMPLATE.read_bytes())
        executable = self.root / "usr/bin/nyvorel"
        executable.parent.mkdir(parents=True)
        executable.write_text("#!/bin/sh\n")
        executable.chmod(0o755)

    def mutations(self):
        return [args for args in self.calls if args[0] not in {"show", "get-default"}]

    def test_fresh_install_seeds_nyvorel_and_enables_next_boot(self):
        self.install_source()
        self.assertIn(f"Exec={login.LOCAL_LAUNCHER}\n", self.session.read_text())
        self.assertIn(f"TryExec={login.LOCAL_LAUNCHER}\n", self.session.read_text())
        self.assertEqual(self.saved_session.read_text(), f"[Last]\nSession={login.LOCAL_SESSION}\n")
        self.assertEqual(self.saved_session.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.mutations(), [
            ("enable", "sddm.service"), ("set-default", "graphical.target"),
        ])

        home = self.root / "user with spaces"
        entry = home / ".local/bin/nyvorel"
        entry.parent.mkdir(parents=True)
        entry.write_text("#!/bin/sh\nprintf '%s\n' \"$@\"\n")
        entry.chmod(0o755)
        output = subprocess.check_output([self.launcher], env=dict(os.environ, HOME=str(home)), text=True)
        self.assertEqual(output.strip(), "session")

    def test_existing_display_manager_and_session_preference_are_preserved(self):
        for manager in ("gdm.service", "sddm.service"):
            with self.subTest(manager=manager):
                self.manager = manager
                self.saved_session.parent.mkdir(parents=True, exist_ok=True)
                self.saved_session.write_text("[Last]\nSession=/usr/share/wayland-sessions/other.desktop\n")
                self.install_source()
                self.assertTrue(self.session.is_file())
                self.assertEqual(self.mutations(), [])
                self.assertIn("/other.desktop", self.saved_session.read_text())

    def test_running_sddm_without_alias_is_preserved(self):
        self.active = True
        self.install_source()
        self.assertFalse(self.saved_session.exists())
        self.assertEqual(self.mutations(), [])

    def test_preserves_previous_session_when_enabling_sddm(self):
        self.default = "graphical.target"
        self.saved_session.parent.mkdir(parents=True)
        self.saved_session.write_text("[Last]\nSession=other.desktop\n")
        self.install_source()
        self.assertEqual(self.saved_session.read_text(), "[Last]\nSession=other.desktop\n")
        self.assertEqual(self.mutations(), [("enable", "sddm.service")])

    def test_failed_boot_setup_rolls_back_registration(self):
        self.fail_default = True
        with self.assertRaises(subprocess.CalledProcessError):
            self.install_source()
        self.assertEqual(self.mutations()[-1], ("disable", "sddm.service"))
        self.assertFalse(self.session.exists())
        self.assertFalse(self.launcher.exists())
        self.assertFalse(self.saved_session.exists())

    def test_custom_session_entry_is_never_overwritten(self):
        self.session.parent.mkdir(parents=True)
        self.session.write_text("local selection\n")
        with self.assertRaisesRegex(RuntimeError, "Refusing to replace"):
            self.install_source()
        self.assertEqual(self.session.read_text(), "local selection\n")
        self.assertFalse(self.launcher.exists())
        self.assertEqual(self.mutations(), [])

    def test_broken_display_manager_alias_is_preserved(self):
        alias = self.root / "etc/systemd/system/display-manager.service"
        alias.parent.mkdir(parents=True)
        alias.symlink_to("missing.service")
        with self.assertRaisesRegex(RuntimeError, "systemd cannot load"):
            self.install_source()
        self.assertTrue(alias.is_symlink())
        self.assertFalse(self.session.exists())
        self.assertEqual(self.mutations(), [])

    def test_packaged_entry_uses_system_cli(self):
        self.install_packaged_entry()
        login.configure("package", root=self.root)
        self.assertEqual(self.saved_session.read_text(), f"[Last]\nSession={login.PACKAGE_SESSION}\n")
        self.assertFalse(self.launcher.exists())

    def test_packaged_setup_after_source_keeps_session_path(self):
        self.install_source()
        self.install_packaged_entry()
        self.manager = "sddm.service"
        login.configure("package", root=self.root)
        self.assertEqual(self.saved_session.read_text(), f"[Last]\nSession={login.LOCAL_SESSION}\n")
        self.assertIn("exec /usr/bin/nyvorel session", self.launcher.read_text())


if __name__ == "__main__":
    unittest.main()
