#!/usr/bin/env python3
"""Serve/Funnel privacy classification parity with disposable Tailscale output."""
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


def rust(binary):
    result = subprocess.run([str(RUST), "serve-funnel", str(binary or "")],
                            capture_output=True, text=True, check=True, timeout=17)
    assert result.stderr == "", result.stderr
    return json.loads(result.stdout)


def expected(binary):
    return {"serve": controller.serve_state(binary), "funnel": controller.funnel_state(binary)}


def main():
    controller.RUST_SERVE_FUNNEL_BIN = RUST
    assert rust(None) == expected(None)
    with tempfile.TemporaryDirectory(prefix="nyvorel-arch-serve-funnel-") as directory:
        root = Path(directory)
        binary = root / "tailscale"
        binary.write_text('#!/bin/sh\ncase "$*" in\n'
                          '"serve status --json") /bin/cat "$TS_JSON";;\n'
                          '"serve status") /bin/cat "$TS_SERVE";;\n'
                          '"funnel status") /bin/cat "$TS_FUNNEL";;\n'
                          'esac\n', encoding="utf-8")
        binary.chmod(0o755)
        paths = {key: root / key for key in ("json", "serve", "funnel")}
        os.environ.update(TS_JSON=str(paths["json"]), TS_SERVE=str(paths["serve"]), TS_FUNNEL=str(paths["funnel"]))
        cases = [
            ({}, "No serve config", "No funnel config"),
            ({"Web": {"host.ts.net:443": {"Handlers": {"/": {"Proxy": "http://192.0.2.1:8000"}}}}},
             "https://host.ts.net (tailnet only)\nproxy http://192.0.2.1:8000", "https://host.ts.net (tailnet only)"),
            ({"Web": {"host.ts.net:443": {"Handlers": {"/share": {"Proxy": "http://192.0.2.2:8000"}}}}},
             "https://host.ts.net (available on the internet)", "https://host.ts.net (available on the internet)"),
            ({"TCP": {"443": {}}}, "Serve configured with no privacy marker", "unknown"),
            ({}, "https://host.ts.net\nproxy http://192.0.2.1:8000", "public route"),
            ({"Web": {"host.ts.net:443": {"Handlers": {"/": {"Proxy": "http://192.0.2.1:8000"}}}}},
             "tailnet only", "tailnet only\npublic status text takes lower priority"),
        ]
        for payload, serve_text, funnel_text in cases:
            paths["json"].write_text(json.dumps(payload), encoding="utf-8")
            paths["serve"].write_text(serve_text, encoding="utf-8")
            paths["funnel"].write_text(funnel_text, encoding="utf-8")
            assert rust(binary) == expected(str(binary)), (serve_text, funnel_text)
            serve, funnel = controller.snapshot_serve_funnel(str(binary))
            assert {"serve": serve, "funnel": funnel} == expected(str(binary))
        paths["json"].write_text("invalid-json", encoding="utf-8")
        paths["serve"].write_text("https://host.ts.net (tailnet only)\nproxy http://127.0.0.1:1", encoding="utf-8")
        paths["funnel"].write_text("No funnel config", encoding="utf-8")
        assert dict(zip(("serve", "funnel"), controller.snapshot_serve_funnel(str(binary)))) == expected(str(binary))
        bad = root / "bad-rust"
        bad.write_text("#!/bin/sh\necho invalid-json\n", encoding="utf-8")
        bad.chmod(0o755)
        controller.RUST_SERVE_FUNNEL_BIN = bad
        assert dict(zip(("serve", "funnel"), controller.snapshot_serve_funnel(str(binary)))) == expected(str(binary))
    print("Arch Remote Serve/Funnel privacy parity and fallback: passed")


if __name__ == "__main__":
    main()
