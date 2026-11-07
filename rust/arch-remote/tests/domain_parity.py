#!/usr/bin/env python3
"""Service-readiness parity, including ownership and private-share gates."""
import importlib.util
import itertools
import json
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


def rust(values):
    result = subprocess.run([str(RUST), "service-domain"], input=json.dumps(values),
                            capture_output=True, text=True, check=True, timeout=5)
    assert result.stderr == "", result.stderr
    return json.loads(result.stdout)


def expected(values):
    return controller.service_domain(values["services"], values["tailscale"], values["exposure"],
                                     values["graphical"], values["ssh"], values["wayvnc_security"])


def wrapped(values):
    return controller.snapshot_service_domain(values["services"], values["tailscale"], values["exposure"],
                                              values["graphical"], values["ssh"], values["wayvnc_security"])


def main():
    controller.RUST_DOMAIN_BIN = RUST
    cases = 0
    for running, connected, private, auth, owner in itertools.product((False, True), repeat=5):
        services = {key: {"running": running,
                          "expected_state": "on-demand" if key in ("lan_share", "wayvnc") else "always-on",
                          "pid": 123} for key in ("sshd", "tailscaled", "lan_share", "wayvnc")}
        listeners = [{"port": port, "endpoint": f"127.0.0.1:{port}", "bind_scope": scope,
                      "pid": 123 if owner else 456, "process": process}
                     for port, scope, process in ((22, "all-interfaces", "sshd"),
                                                  (8000, "loopback", "python3"), (5900, "tailnet", "wayvnc"))]
        values = {
            "services": services,
            "tailscale": {"connected": connected,
                          "serve": {"configured": private, "tailnet_only": private,
                                    "verification": "tailnet-only" if private else "unknown",
                                    "upstream_reachable": private},
                          "funnel": {"verification": "off", "is_public": False}},
            "exposure": {"listeners": listeners},
            "graphical": {"hyprland_available": True, "wayland_display": "wayland-1"},
            "ssh": {"effective_verified": auth, "secure": auth},
            "wayvnc_security": {"ok": auth, "auth_mode": "tls", "username": "test",
                                 "tailnet_acl_verification": "external-unverified"},
        }
        assert rust(values) == expected(values)
        assert wrapped(values) == expected(values)
        cases += 1
    with tempfile.TemporaryDirectory(prefix="nyvorel-arch-domain-") as directory:
        bad = Path(directory) / "bad"
        bad.write_text("#!/bin/sh\necho invalid-json\n", encoding="utf-8")
        bad.chmod(0o755)
        controller.RUST_DOMAIN_BIN = bad
        assert wrapped(values) == expected(values)
    print(f"Arch Remote service readiness and fallback parity: {cases} cases passed")


if __name__ == "__main__":
    main()
