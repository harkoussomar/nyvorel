#!/usr/bin/env python3
"""One-process live derivation parity with synthetic evidence and isolated activity state."""
import copy
import itertools
import json
from pathlib import Path
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from audit_parity import baseline as audit_baseline, controller, RUST  # noqa: E402
from phone_guide_parity import SUPPORT  # noqa: E402


def fixture():
    source = audit_baseline()
    services = source["services"]
    for key in services:
        services[key].update(running=True, expected_state="on-demand" if key in ("lan_share", "wayvnc") else "always-on", pid=123)
    source["tailscale"].update(dns_name="pc.example.ts.net", hostname="pc", ipv4="100.1.2.4",
                               phone={"hostname": "phone", "online": True, "addresses": ["100.1.2.3"]},
                               devices=[{"hostname": "phone", "online": True, "is_self": False}])
    source["tailscale"]["serve"].update(url="https://pc.example.ts.net/", health="healthy",
                                         upstream="http://127.0.0.1:8000", upstream_reachable=True)
    source["exposure"].update(listeners=[
        {"port": port, "endpoint": f"127.0.0.1:{port}", "address": "127.0.0.1",
         "bind_scope": scope, "pid": 123, "process": process}
        for port, scope, process in ((22, "all-interfaces", "sshd"), (8000, "loopback", "python3"),
                                     (5900, "tailnet", "wayvnc"))])
    source["graphical"] = {"hyprland_available": True, "wayland_display": "wayland-1"}
    source["host"] = {"hostname": "pc"}
    source["wayvnc_security"].update(auth_mode="tls", username="omar")
    source["slow"].update(checked_at=123400.0,
                          ssh_auth={"last_success_ip": "100.1.2.3", "last_success_at": 12345, "failure_count": 0},
                          ssh_host_fingerprint={"fingerprint": "SHA256:test"},
                          interfaces=[], wake={"wifi": {"configured": True}},
                          lid={"status": "safe"})
    source["slow"]["ssh"].update(secure=True, authorized_keys_exists=True)
    source.update(raw_services=source.pop("services"), integrity=source["integrity"],
                  listeners=source["exposure"]["listeners"], support=SUPPORT,
                  qrencode_available=True, home=str(controller.HOME),
                  checked_at=123456.5, activity_now=123456.75, generation=7,
                  schema_version=controller.STATE_SCHEMA_VERSION, ui_contract=controller.UI_CONTRACT,
                  backend_revision=controller.BACKEND_REVISION,
                  activity_existing={"previous": {}, "events": []})
    return source


def normalize(state):
    result = copy.deepcopy(state)
    for check in result["security_checks"]:
        check.pop("checked_at", None)
    return result


def rust(source):
    result = subprocess.run([str(RUST), "live-derive"], input=json.dumps(source), text=True,
                            capture_output=True, check=True, timeout=6)
    assert result.stderr == "", result.stderr
    return json.loads(result.stdout)


def main():
    count = 0
    with tempfile.TemporaryDirectory(prefix="nyvorel-live-derive-") as directory:
        base = Path(directory)
        controller.STATE_DIR = base
        controller.ACTIVITY_FILE = base / "activity.json"
        controller.STATE_DATA_LOCK = base / "state.lock"
        controller.RUST_LIVE_DERIVE_BIN = RUST
        controller.snapshot_pair_command_support = lambda: SUPPORT
        controller.exe = lambda name: "/usr/bin/qrencode" if name == "qrencode" else None
        controller.time.time = lambda: 123456.75

        def compare(source):
            nonlocal count
            raw = source["raw_services"]
            ts = source["tailscale"]
            exp = source["exposure"]
            slow = source["slow"]
            checks = controller.security_audit(raw, ts, exp, slow, source["wayvnc_security"],
                                               source["hardening"], source["integrity"])
            health = controller.health_summary(checks, ts)
            services = controller.service_domain(raw, ts, exp, source["graphical"], slow["ssh"],
                                                 source["wayvnc_security"])
            expected = {"schema_version": source["schema_version"], "ui_contract": source["ui_contract"],
                        "backend_revision": source["backend_revision"], "generation": source["generation"],
                        "generated_at": source["checked_at"], "fast_checked_at": source["checked_at"],
                        "slow_checked_at": slow["checked_at"], "health": health,
                        "profile": "Remote desktop" if services["wayvnc"]["ready"] else "File sharing" if services["lan_share"]["reachable"] else "Secure idle" if services["sshd"]["running"] and ts["connected"] else "Custom",
                        "host": source["host"], "services": services, "tailscale": ts,
                        "listeners": source["listeners"], "exposure": exp, "security_checks": checks,
                        "ssh": slow["ssh"], "ssh_auth": slow["ssh_auth"],
                        "ssh_host_fingerprint": slow["ssh_host_fingerprint"],
                        "interfaces": slow["interfaces"], "wake": slow["wake"],
                        "linger": slow["linger"], "lid": slow["lid"],
                        "graphical": source["graphical"], "wayvnc_security": source["wayvnc_security"],
                        "hardening": source["hardening"], "deployment_integrity": source["integrity"]}
            expected["phone_guide"] = controller.phone_guide(expected, slow)
            controller.ACTIVITY_FILE.write_text(json.dumps(source["activity_existing"]), encoding="utf-8")
            expected["activity"] = controller._activity_state_unlocked(expected)
            expected["cache"] = {"source": "live", "age_seconds": 0.0,
                                 "current_backend_revision": source["backend_revision"],
                                 "cached_backend_revision": source["backend_revision"]}
            expected_activity = json.loads(controller.ACTIVITY_FILE.read_text(encoding="utf-8"))
            actual = rust(source)
            assert normalize(actual["state"]) == normalize(expected), {
                key: (expected.get(key), actual["state"].get(key)) for key in expected
                if normalize({"security_checks": expected["security_checks"], key: expected[key]}) !=
                   normalize({"security_checks": actual["state"]["security_checks"], key: actual["state"].get(key)})}
            assert actual["activity"] == expected_activity
            controller.ACTIVITY_FILE.write_text(json.dumps(source["activity_existing"]), encoding="utf-8")
            wrapped = controller.snapshot_live_derive(source["checked_at"], source["generation"], raw, ts,
                                                       source["listeners"], exp, source["host"], source["graphical"],
                                                       slow, source["wayvnc_security"], source["hardening"], source["integrity"])
            assert wrapped is not None
            assert normalize(wrapped) == normalize(expected)
            assert json.loads(controller.ACTIVITY_FILE.read_text(encoding="utf-8")) == expected_activity
            count += 1

        base_source = fixture()
        compare(base_source)
        changes = (
            lambda x: x["raw_services"]["wayvnc"].update(running=False),
            lambda x: x["raw_services"]["lan_share"].update(running=False),
            lambda x: x["tailscale"].update(connected=False),
            lambda x: x["tailscale"]["funnel"].update(verification="public", is_public=True),
            lambda x: x["slow"]["ssh"].update(secure=False, effective_verified=False),
            lambda x: x["wayvnc_security"].update(ok=False),
            lambda x: x["integrity"].update(ok=False),
            lambda x: x["exposure"]["groups"].update(unexpected=[{"endpoint": "0.0.0.0:5900"}]),
        )
        for change in changes:
            variant = copy.deepcopy(base_source)
            change(variant)
            compare(variant)
        for first, second in itertools.combinations(changes, 2):
            variant = copy.deepcopy(base_source)
            first(variant)
            second(variant)
            compare(variant)
        invalid = base / "invalid-rust"
        invalid.write_text("#!/bin/sh\necho invalid-json\n", encoding="utf-8")
        invalid.chmod(0o755)
        controller.RUST_LIVE_DERIVE_BIN = invalid
        before = controller.ACTIVITY_FILE.read_bytes()
        assert controller.snapshot_live_derive(base_source["checked_at"], base_source["generation"],
                                               base_source["raw_services"], base_source["tailscale"],
                                               base_source["listeners"], base_source["exposure"],
                                               base_source["host"], base_source["graphical"],
                                               base_source["slow"], base_source["wayvnc_security"],
                                               base_source["hardening"], base_source["integrity"]) is None
        assert controller.ACTIVITY_FILE.read_bytes() == before
    print(f"Arch Remote combined live derivation and fallback parity: {count} cases passed")


if __name__ == "__main__":
    main()
