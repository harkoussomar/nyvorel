#!/usr/bin/env python3
"""On-demand reference parity across dynamic fields and secret-rejection cases."""
import copy
import importlib.util
import itertools
import json
import shlex
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
    return {"generation": 17, "phone_guide": {
        "host": "pc.example.ts.net", "share": {"url": "https://pc.example.ts.net/"},
        "vnc": {"endpoint": "pc.example.ts.net:5900"},
        "sftp": {"fingerprint": "SHA256:example", "root_path": str(controller.HOME)},
        "user": controller.USER, "ssh_config": "Host arch-pc\n    HostName pc.example.ts.net"},
        "tailscale": {"dns_name": "pc.example.ts.net", "hostname": "pc", "ipv4": "100.1.2.3"},
        "services": {"lan_share": {"running": True, "ready": True},
                     "wayvnc": {"running": True, "ready": True,
                                "auth_mode": "tls", "auth_username": "omar"}},
        "wake": {"wifi": {"phy": "phy0"}, "ethernet": {"interface_name": "enp2s0"}},
        "lid": {"status": "configured"}, "host": {"hostname": "pc"}}


def rust(state):
    result = subprocess.run([str(RUST), "reference-model"], input=json.dumps({"state": state,
                           "user": controller.USER, "home": str(controller.HOME)}),
                           text=True, capture_output=True, check=True, timeout=5)
    assert result.stderr == "", result.stderr
    return json.loads(result.stdout)


def comparable(value):
    result = copy.deepcopy(value)
    result.pop("generated_at", None)
    return result


def main():
    wrapper_dir = tempfile.TemporaryDirectory(prefix="nyvorel-reference-model-")
    wrapper = Path(wrapper_dir.name) / "rust-reference-model"
    wrapper.write_text(f"#!/bin/sh\nshift\nexec {shlex.quote(str(RUST))} reference-model \"$@\"\n")
    wrapper.chmod(0o755)
    controller.RUST_REFERENCE_BIN = wrapper
    count = 0

    def compare(state):
        nonlocal count
        expected = controller.reference_model(state)
        actual = rust(state)
        assert comparable(actual) == comparable(expected), {
            key: (expected.get(key), actual.get(key)) for key in expected
            if comparable({key: expected[key]}) != comparable({key: actual.get(key)})}
        assert comparable(controller.snapshot_reference_model(state)) == comparable(expected)
        count += 1

    base = baseline()
    compare(base)
    changes = (
        lambda x: x["services"]["lan_share"].update(running=False, ready=False),
        lambda x: x["services"]["wayvnc"].update(running=False, ready=False),
        lambda x: x["phone_guide"]["share"].update(url=""),
        lambda x: x["phone_guide"]["vnc"].update(endpoint=""),
        lambda x: x["phone_guide"]["sftp"].update(fingerprint=""),
        lambda x: x["phone_guide"].update(ssh_config=""),
        lambda x: x["wake"]["wifi"].update(phy=""),
        lambda x: x["wake"]["ethernet"].update(interface_name=""),
        lambda x: x["lid"].update(status=""),
        lambda x: x["phone_guide"].update(host=""),
    )
    for size in (1, 2):
        for group in itertools.combinations(changes, size):
            variant = copy.deepcopy(base)
            for change in group:
                change(variant)
            compare(variant)
    secret = copy.deepcopy(base)
    secret["phone_guide"]["share"]["url"] = "https://pc.example.ts.net/pair#t=secret123456"
    try:
        controller.reference_model(secret)
    except ValueError:
        pass
    else:
        raise AssertionError("Python reference accepted one-time credential")
    assert rust(secret).get("error") is True
    with tempfile.TemporaryDirectory(prefix="nyvorel-arch-reference-") as directory:
        bad = Path(directory) / "bad"
        bad.write_text("#!/bin/sh\necho invalid-json\n", encoding="utf-8")
        bad.chmod(0o755)
        controller.RUST_REFERENCE_BIN = bad
        assert comparable(controller.snapshot_reference_model(base)) == comparable(controller.reference_model(base))
    print(f"Arch Remote reference model and fallback parity: {count} cases passed")


if __name__ == "__main__":
    main()
