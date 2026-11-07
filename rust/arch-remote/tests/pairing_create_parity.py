#!/usr/bin/env python3
"""Pairing protocol parity with fake binaries; never invokes live LAN Share."""
import importlib.util
import json
import os
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
NOW = 123456
TOKEN = "synthetic-token-only-for-tests"
SERVE_URL = "https://pc.example.ts.net/"
PAIR_URL = f"https://pc.example.ts.net/pair#t={TOKEN}"


def main():
    count = 0
    with tempfile.TemporaryDirectory(prefix="nyvorel-pair-protocol-") as directory:
        folder = Path(directory)
        response = folder / "pair-response.json"
        capture = folder / "qr-stdin"
        pair = folder / "fake-pair"
        qr = folder / "fake-qr"
        pair.write_text("#!/usr/bin/env python3\nimport os,sys\n"
                        "assert sys.argv[1:] == ['pair','--json']\n"
                        "sys.stdout.write(open(os.environ['PAIR_RESPONSE']).read())\n"
                        "sys.exit(int(os.environ.get('PAIR_EXIT','0')))\n", encoding="utf-8")
        qr.write_text("#!/usr/bin/env python3\nimport os,sys\n"
                      "assert sys.argv[1:] == ['-o','-','-t','PNG','-s','7','-m','2']\n"
                      "open(os.environ['QR_CAPTURE'],'wb').write(sys.stdin.buffer.read())\n"
                      "if os.environ.get('QR_EXIT') == '1': sys.exit(1)\n"
                      "sys.stdout.buffer.write(b'\\x89PNG\\r\\n\\x1a\\nsynthetic')\n", encoding="utf-8")
        pair.chmod(0o700)
        qr.chmod(0o700)
        os.environ.update(PAIR_RESPONSE=str(response), QR_CAPTURE=str(capture))
        checks = {key: True for key in ("service_ready", "listener_ready", "serve_configured",
                  "serve_tailnet_only", "funnel_private_verified", "private_exposure_verified",
                  "serve_url_safe", "upstream_is_lan_share", "qrencode_available",
                  "pair_executable_found", "pair_command_supported")}
        readiness = {"available": True, "reason": "Ready for one-scan pairing.", "checks": checks,
                     "serve_url": SERVE_URL, "pair_binary": str(pair), "pair_support_status": "supported"}
        support = {"available": True, "cancel_supported": True, "binary": str(pair)}
        controller.snapshot = lambda force=False: {}
        controller.snapshot_private_share_pairing_readiness = lambda state: readiness
        controller.snapshot_pair_command_support = lambda: support
        controller.exe = lambda name: str(qr) if name == "qrencode" else None
        controller.record_activity = lambda *args: None
        controller.time.time = lambda: NOW
        rust_model = folder / "rust-pairing-create-model"
        rust_model.write_text(f"#!/bin/sh\nshift\nexec {shlex.quote(str(RUST))} pairing-create-model \"$@\"\n")
        rust_model.chmod(0o700)
        controller.RUST_PAIRING_CREATE_BIN = rust_model

        def compare(payload, success):
            nonlocal count
            response.write_text(json.dumps(payload) if isinstance(payload, dict) else payload, encoding="utf-8")
            rust_result = controller.pairing_create()
            controller.RUST_PAIRING_CREATE_BIN = folder / "missing-binary"
            python_result = controller.pairing_create()
            controller.RUST_PAIRING_CREATE_BIN = rust_model
            assert rust_result == python_result, (rust_result, python_result)
            assert rust_result.get("ok") is success
            if success:
                assert capture.read_text(encoding="utf-8") == PAIR_URL
                assert TOKEN not in rust_result["qr_data_url"]
            else:
                assert TOKEN not in json.dumps(rust_result)
            count += 1

        base = {"pair_url": PAIR_URL, "expires_at": NOW + 300, "expires_in": 300, "single_use": True}
        compare(base, True)
        for variant in (
            {**base, "pair_url": "https://evil.example/pair#t=" + TOKEN},
            {**base, "pair_url": "https://pc.example.ts.net/other#t=" + TOKEN},
            {**base, "pair_url": "https://pc.example.ts.net/pair?x=1#t=" + TOKEN},
            {**base, "single_use": False},
            {**base, "expires_at": NOW - 1},
            {**base, "expires_at": NOW + 901},
            {**base, "expires_in": 901},
            {**base, "expires_in": "invalid"},
            "not-json",
        ):
            compare(variant, False)
        os.environ["PAIR_EXIT"] = "1"
        compare(base, False)
        os.environ.pop("PAIR_EXIT")
        os.environ["QR_EXIT"] = "1"
        compare(base, False)
        os.environ.pop("QR_EXIT")
        bad = folder / "invalid-rust"
        bad.write_text("#!/bin/sh\necho invalid-json\n", encoding="utf-8")
        bad.chmod(0o700)
        controller.RUST_PAIRING_CREATE_BIN = bad
        response.write_text(json.dumps(base), encoding="utf-8")
        assert controller.pairing_create()["message"] == "Pairing backend failed. Retry to generate a fresh QR."
    print(f"Arch Remote secret-safe pairing protocol parity: {count} cases passed")


if __name__ == "__main__":
    main()
