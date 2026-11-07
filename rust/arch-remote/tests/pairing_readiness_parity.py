#!/usr/bin/env python3
"""Private pairing gate parity; no credential-creating commands are executed."""
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
    return {"services": {"lan_share": {"ready": True, "listeners": [{"address": "127.0.0.1", "port": 8000}]}},
            "tailscale": {"serve": {"configured": True, "tailnet_only": True,
                                    "verification": "tailnet-only", "url": "https://pc.example.ts.net/",
                                    "upstream": "http://127.0.0.1:8000"},
                          "funnel": {"verification": "off", "is_public": False}}}


def rust(state, support, qr):
    result = subprocess.run([str(RUST), "pairing-readiness"],
                            input=json.dumps({"state": state, "support": support, "qrencode_available": qr}),
                            text=True, capture_output=True, check=True, timeout=5)
    assert result.stderr == "", result.stderr
    return json.loads(result.stdout)


def main():
    controller.RUST_PAIRING_READINESS_BIN = RUST
    selected_support = copy.deepcopy(SUPPORT)
    selected_qr = True
    controller.snapshot_pair_command_support = lambda: selected_support
    controller.exe = lambda name: "/usr/bin/qrencode" if name == "qrencode" and selected_qr else None
    count = 0

    def compare(state):
        nonlocal count
        expected = controller.private_share_pairing_readiness(state)
        actual = rust(state, selected_support, selected_qr)
        assert actual == expected, {key: (expected[key], actual.get(key)) for key in expected if expected[key] != actual.get(key)}
        assert controller.snapshot_private_share_pairing_readiness(state) == expected
        count += 1

    value = baseline()
    compare(value)
    changes = (
        lambda x: x["services"]["lan_share"].update(ready=False),
        lambda x: x["services"]["lan_share"].update(listeners=[]),
        lambda x: x["services"]["lan_share"].update(listeners=[{"address": "0.0.0.0", "port": 8000}]),
        lambda x: x["tailscale"]["serve"].update(configured=False),
        lambda x: x["tailscale"]["serve"].update(tailnet_only=False),
        lambda x: x["tailscale"]["funnel"].update(is_public=True, verification="public"),
        lambda x: x["tailscale"]["serve"].update(upstream="http://0.0.0.0:8000"),
    )
    for size in (1, 2):
        for group in itertools.combinations(changes, size):
            variant = copy.deepcopy(value)
            for change in group:
                change(variant)
            compare(variant)
    for url in ("https://pc.example.ts.net", "https://pc.example.ts.net/pair",
                "https://PC.EXAMPLE.TS.NET/a", "https://pc.example.ts.net:443/path",
                "https://pc.example.ts.net/?", "https://pc.example.ts.net/#",
                "https://user@pc.example.ts.net/", "https://pc.example.ts.net/?token=secret",
                "https://pc.example.ts.net/#fragment", "https://pc.example.ts.net.evil/",
                "http://pc.example.ts.net/", "not-a-url", ""):
        variant = copy.deepcopy(value)
        variant["tailscale"]["serve"]["url"] = url
        compare(variant)
    selected_support = {**SUPPORT, "available": False, "status": "unsupported"}
    compare(value)
    selected_support = {**SUPPORT, "installed": False, "available": False, "binary": "", "status": "missing"}
    compare(value)
    selected_support = copy.deepcopy(SUPPORT)
    selected_qr = False
    compare(value)
    with tempfile.TemporaryDirectory(prefix="nyvorel-arch-pair-gate-") as directory:
        invalid = Path(directory) / "invalid-rust"
        invalid.write_text("#!/bin/sh\necho invalid-json\n", encoding="utf-8")
        invalid.chmod(0o755)
        controller.RUST_PAIRING_READINESS_BIN = invalid
        assert controller.snapshot_private_share_pairing_readiness(value) == controller.private_share_pairing_readiness(value)
    print(f"Arch Remote private pairing readiness and fallback parity: {count} cases passed")


if __name__ == "__main__":
    main()
