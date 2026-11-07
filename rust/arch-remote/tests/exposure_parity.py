#!/usr/bin/env python3
"""Security classification and fallback parity across listener/funnel states."""
import importlib.util
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


def rust(listeners, tailscale, binary=RUST):
    output = subprocess.run([str(binary), "exposure"],
                            input=json.dumps({"listeners": listeners, "tailscale": tailscale}),
                            text=True, capture_output=True, check=True, timeout=5)
    assert output.stderr == "", output.stderr
    return json.loads(output.stdout)


def main():
    controller.RUST_EXPOSURE_BIN = RUST
    cases = 0
    for scope in ("loopback", "tailnet", "all-interfaces", "specific"):
        for port in (22, 8000, 5900, 443, 1234):
            for verification in ("off", "tailnet-only", "public", "unknown"):
                for public in (False, True):
                    listeners = [{"port": port, "bind_scope": scope,
                                  "address": "100.101.102.103" if scope == "tailnet" else "0.0.0.0",
                                  "process": "tester"}]
                    tailscale = {"ipv4": "100.101.102.103", "ipv6": "fd7a::1",
                                 "funnel": {"is_public": public, "verification": verification}}
                    expected = controller.exposure_state(listeners, tailscale)
                    assert rust(listeners, tailscale) == expected
                    assert controller.snapshot_exposure_state(listeners, tailscale) == expected
                    cases += 1
    with tempfile.TemporaryDirectory(prefix="nyvorel-arch-exposure-") as directory:
        bad = Path(directory) / "bad"
        bad.write_text("#!/bin/sh\necho invalid-json\n", encoding="utf-8")
        bad.chmod(0o755)
        controller.RUST_EXPOSURE_BIN = bad
        assert controller.snapshot_exposure_state(listeners, tailscale) == expected
    print(f"Arch Remote exposure classification and fallback parity: {cases} cases passed")


if __name__ == "__main__":
    main()
