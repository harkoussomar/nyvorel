#!/usr/bin/env python3
"""Phone-guide parity using synthetic evidence; no services or credentials touched."""
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

SUPPORT = {"installed": True, "available": True, "cancel_supported": True,
           "binary": "/tmp/lan-share", "status": "supported"}


def baseline():
    state = {"services": {
        "sshd": {"ready": True},
        "wayvnc": {"ready": True, "running": True, "graphical_ready": True,
                   "transport_ready": True, "auth_ready": True, "auth_mode": "tls",
                   "auth_username": "omar", "readiness_reason": ""},
        "lan_share": {"ready": True, "running": True, "reachable": True,
                      "listeners": [{"address": "127.0.0.1", "port": 8000}]}},
        "tailscale": {"dns_name": "arch-pc.example.ts.net", "hostname": "arch-pc", "connected": True,
                      "phone": {"online": True, "addresses": ["100.1.2.3"]},
                      "serve": {"configured": True, "tailnet_only": True, "verification": "tailnet-only",
                                "url": "https://arch-pc.example.ts.net/", "upstream": "http://127.0.0.1:8000",
                                "upstream_reachable": True},
                      "funnel": {"verification": "off", "is_public": False}},
        "host": {"hostname": "arch-pc"}}
    slow = {"ssh_auth": {"last_success_ip": "100.1.2.3", "last_success_at": 12345},
            "ssh": {"authorized_keys_exists": True},
            "ssh_host_fingerprint": {"fingerprint": "SHA256:example", "key_type": "ED25519"}}
    return state, slow


def rust(state, slow, support, qr):
    payload = {"state": state, "slow": slow, "support": support, "qrencode_available": qr,
               "user": controller.USER, "home": str(controller.HOME)}
    result = subprocess.run([str(RUST), "phone-guide"], input=json.dumps(payload), text=True,
                            capture_output=True, check=True, timeout=5)
    assert result.stderr == "", result.stderr
    return json.loads(result.stdout)


def main():
    controller.RUST_PHONE_GUIDE_BIN = RUST
    support = copy.deepcopy(SUPPORT)
    qr = True
    controller.snapshot_pair_command_support = lambda: support
    controller.exe = lambda name: "/usr/bin/qrencode" if name == "qrencode" and qr else None
    count = 0

    def compare(state, slow):
        nonlocal count
        expected = controller.phone_guide(state, slow)
        actual = rust(state, slow, support, qr)
        assert actual == expected, {key: (expected[key], actual.get(key)) for key in expected if expected[key] != actual.get(key)}
        assert controller.snapshot_phone_guide(state, slow) == expected
        count += 1

    base_state, base_slow = baseline()
    compare(base_state, base_slow)
    changes = (
        lambda s, w: s["services"]["wayvnc"].update(ready=False, running=False),
        lambda s, w: s["services"]["wayvnc"].update(ready=False, auth_ready=False),
        lambda s, w: s["services"]["wayvnc"].update(ready=False, graphical_ready=False),
        lambda s, w: s["services"]["sshd"].update(ready=False),
        lambda s, w: s["services"]["lan_share"].update(reachable=False),
        lambda s, w: s["tailscale"].update(connected=False),
        lambda s, w: s["tailscale"].update(phone={}),
        lambda s, w: s["tailscale"]["phone"].update(online=False),
        lambda s, w: s["tailscale"]["funnel"].update(verification="public", is_public=True),
        lambda s, w: w["ssh_auth"].update(last_success_ip=""),
        lambda s, w: w["ssh"].update(authorized_keys_exists=False),
    )
    for size in (1, 2):
        for group in itertools.combinations(changes, size):
            state, slow = copy.deepcopy((base_state, base_slow))
            for change in group:
                change(state, slow)
            compare(state, slow)
    for dns, hostname in (("", "arch-pc"), ("", "")):
        state, slow = copy.deepcopy((base_state, base_slow))
        state["tailscale"].update(dns_name=dns, hostname=hostname)
        compare(state, slow)
    support = {**SUPPORT, "cancel_supported": False, "available": False, "status": "unsupported"}
    compare(base_state, base_slow)
    qr = False
    compare(base_state, base_slow)
    with tempfile.TemporaryDirectory(prefix="nyvorel-phone-guide-") as directory:
        invalid = Path(directory) / "invalid-rust"
        invalid.write_text("#!/bin/sh\necho invalid-json\n", encoding="utf-8")
        invalid.chmod(0o755)
        controller.RUST_PHONE_GUIDE_BIN = invalid
        assert controller.snapshot_phone_guide(base_state, base_slow) == controller.phone_guide(base_state, base_slow)
    print(f"Arch Remote phone guide and fallback parity: {count} cases passed")


if __name__ == "__main__":
    main()
