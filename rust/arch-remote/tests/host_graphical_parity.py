#!/usr/bin/env python3
"""Host and Wayland read-only collector parity with disposable Hyprland output."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[3]
PYTHON = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else ROOT / "quickshell/scripts/arch-remote/control_center.py"
RUST = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "target/release/nyvorel-arch-remote"
spec = importlib.util.spec_from_file_location("arch_remote", PYTHON)
controller = importlib.util.module_from_spec(spec)
spec.loader.exec_module(controller)


def rust():
    result = subprocess.run([str(RUST), "host-graphical"], capture_output=True, text=True, check=True, timeout=10)
    assert result.stderr == "", result.stderr
    return json.loads(result.stdout)


def compare(actual, expected):
    assert actual["graphical"] == expected["graphical"]
    for field in ("hostname", "user", "home", "kernel", "storage"):
        assert actual["host"][field] == expected["host"][field], field
    assert actual["host"]["uptime"] and actual["host"]["load"]


def main():
    controller.RUST_HOST_GRAPHICAL_BIN = RUST
    with tempfile.TemporaryDirectory(prefix="nyvorel-arch-host-") as directory:
        root = Path(directory)
        fake_bin = root / "bin"
        fake_bin.mkdir()
        hyprctl = fake_bin / "hyprctl"
        hyprctl.write_text('#!/bin/sh\n/bin/cat "$ARCH_REMOTE_HYPR_FIXTURE"\n', encoding="utf-8")
        hyprctl.chmod(0o755)
        uname = fake_bin / "uname"
        uname.write_text('#!/bin/sh\necho test-kernel\n', encoding="utf-8")
        uname.chmod(0o755)
        runtime = root / "runtime"
        runtime.mkdir()
        (runtime / "wayland-1").touch()
        (runtime / "wayland-0").touch()
        fixture = root / "hypr.json"
        old = {key: os.environ.get(key) for key in ("PATH", "XDG_RUNTIME_DIR", "WAYLAND_DISPLAY", "ARCH_REMOTE_HYPR_FIXTURE")}
        try:
            os.environ.update(PATH=f"{fake_bin}:/usr/bin:/bin", XDG_RUNTIME_DIR=str(runtime), ARCH_REMOTE_HYPR_FIXTURE=str(fixture))
            for display, monitors in (("", []), ("wayland-2", [{"name": "eDP-1"}])):
                os.environ["WAYLAND_DISPLAY"] = display
                fixture.write_text(json.dumps(monitors), encoding="utf-8")
                expected = {"host": controller.host_state(), "graphical": controller.graphical_state()}
                compare(rust(), expected)
                host, graphical = controller.snapshot_host_graphical()
                compare({"host": host, "graphical": graphical}, expected)
            bad = root / "bad"
            bad.write_text("#!/bin/sh\necho invalid-json\n", encoding="utf-8")
            bad.chmod(0o755)
            controller.RUST_HOST_GRAPHICAL_BIN = bad
            host, graphical = controller.snapshot_host_graphical()
            compare({"host": host, "graphical": graphical}, expected)
        finally:
            for key, value in old.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value
    print("Arch Remote host/graphical collector parity and fallback: passed")


if __name__ == "__main__":
    main()
