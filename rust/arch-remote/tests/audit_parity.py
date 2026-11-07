#!/usr/bin/env python3
"""Security audit and health summary parity over deterministic evidence cases."""
import copy
import importlib.util
import itertools
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[3]
RUST = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "target/release/nyvorel-arch-remote"
PYTHON = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else ROOT / "quickshell/scripts/arch-remote/control_center.py"
spec = importlib.util.spec_from_file_location("arch_remote", PYTHON)
controller = importlib.util.module_from_spec(spec)
spec.loader.exec_module(controller)


def baseline():
    return {
        "services": {"sshd": {"running": True, "active_state": "active"},
                     "tailscaled": {}, "lan_share": {"boot_enabled": False, "enabled_state": "disabled"},
                     "wayvnc": {"boot_enabled": False, "enabled_state": "disabled"}},
        "tailscale": {"connected": True, "backend_state": "Running", "health_messages": [],
                      "funnel": {"is_public": False, "verification": "off", "source": "funnel"},
                      "serve": {"configured": True, "tailnet_only": True, "verification": "tailnet-only",
                                "is_public": False, "source": "serve"}},
        "exposure": {"groups": {"unexpected": []}},
        "slow": {"ssh": {"configured": {"permit_root_login": "no", "password_authentication": "no",
                                         "pubkey_authentication": "yes", "kbd_interactive_authentication": "no",
                                         "allow_users": controller.USER},
                         "effective_verified": True,
                         "effective": {"permit_root_login": "no", "password_authentication": "no",
                                       "pubkey_authentication": "yes", "kbd_interactive_authentication": "no",
                                       "allow_users": controller.USER},
                         "source": "sshd -T", "effective_error": ""},
                 "linger": {"enabled": True, "value": "yes", "source": "loginctl"}},
        "wayvnc_security": {"ok": True, "reason": "verified"},
        "hardening": {"services": {name: {"ok": True, "path": f"/tmp/{name}.conf", "missing": []}
                                  for name in ("lan-share", "wayvnc-remote")}},
        "integrity": {"ok": True, "reason": "All package-owned files match the deployment manifest."},
        "user": controller.USER,
        "paths": {"ssh_dropin": str(controller.SSH_DROPIN),
                  "wayvnc_config": str(controller.WAYVNC_CONFIG),
                  "wayvnc_launcher": str(controller.WAYVNC_LAUNCHER),
                  "wayvnc_dropin": str(controller.WAYVNC_SECURITY_DROPIN),
                  "manifest": str(controller.DEPLOYMENT_MANIFEST)},
    }


def comparable(value):
    value = copy.deepcopy(value)
    for row in value["checks"]:
        row.pop("checked_at", None)
    return value


def compare(input_value):
    expected_checks = controller.security_audit(input_value["services"], input_value["tailscale"],
                                                input_value["exposure"], input_value["slow"],
                                                input_value["wayvnc_security"], input_value["hardening"],
                                                input_value["integrity"])
    expected = {"checks": expected_checks, "health": controller.health_summary(expected_checks, input_value["tailscale"])}
    result = subprocess.run([str(RUST), "security-audit"], input=json.dumps(input_value),
                            text=True, capture_output=True, check=True, timeout=5)
    assert result.stderr == "", result.stderr
    actual = json.loads(result.stdout)
    want, got = comparable(expected), comparable(actual)
    assert len(want["checks"]) == len(got["checks"]), (len(want["checks"]), len(got["checks"]))
    for index, (left, right) in enumerate(zip(want["checks"], got["checks"])):
        assert left == right, (index, left["id"], {key: (left[key], right.get(key)) for key in left if left[key] != right.get(key)})
    assert want["health"] == got["health"], (want["health"], got["health"])
    wrapped_checks, wrapped_health = controller.snapshot_security_audit(
        input_value["services"], input_value["tailscale"], input_value["exposure"],
        input_value["slow"], input_value["wayvnc_security"], input_value["hardening"],
        input_value["integrity"])
    assert comparable({"checks": wrapped_checks, "health": wrapped_health}) == want


def main():
    controller.RUST_AUDIT_BIN = RUST
    value = baseline()
    compare(value)
    variants = []
    changes = (
        lambda x: x["services"]["sshd"].update(running=False, active_state="failed"),
        lambda x: x["tailscale"].update(connected=False, backend_state="NeedsLogin", health_messages=["offline"]),
        lambda x: x["slow"]["ssh"].update(effective_verified=False, effective_error="permission denied"),
        lambda x: x["slow"]["ssh"]["effective"].update(allow_users="someone-else", password_authentication="yes"),
        lambda x: x["tailscale"]["funnel"].update(is_public=True, verification="public"),
        lambda x: x["tailscale"]["serve"].update(tailnet_only=False, verification="unknown"),
        lambda x: x["exposure"]["groups"]["unexpected"].append({"endpoint": "0.0.0.0:5900"}),
        lambda x: x["services"]["lan_share"].update(boot_enabled=True, enabled_state="enabled"),
        lambda x: x["wayvnc_security"].update(ok=False, reason="bad cert"),
        lambda x: x["hardening"]["services"]["lan-share"].update(ok=False, missing=["PrivateTmp=yes"]),
        lambda x: x["integrity"].update(ok=False, reason="drift"),
    )
    for change in changes:
        variant = copy.deepcopy(value)
        change(variant)
        variants.append(variant)
    for first, second in itertools.combinations(changes, 2):
        variant = copy.deepcopy(value)
        first(variant)
        second(variant)
        variants.append(variant)
    for variant in variants:
        compare(variant)
    with tempfile.TemporaryDirectory(prefix="nyvorel-arch-audit-") as directory:
        bad = Path(directory) / "invalid-rust"
        bad.write_text("#!/bin/sh\necho invalid-json\n", encoding="utf-8")
        bad.chmod(0o755)
        controller.RUST_AUDIT_BIN = bad
        compare(value)
    print(f"Arch Remote security audit and health parity: {len(variants)+1} cases passed")


if __name__ == "__main__":
    main()
