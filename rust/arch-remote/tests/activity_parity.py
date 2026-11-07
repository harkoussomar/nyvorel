#!/usr/bin/env python3
"""Activity transition parity with isolated temporary state; no live service calls."""
import copy
import itertools
import json
from pathlib import Path
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from phone_guide_parity import baseline, controller, RUST, PYTHON, SUPPORT  # noqa: E402


def full_baseline():
    state, slow = baseline()
    state.update(ssh_auth=copy.deepcopy(slow["ssh_auth"]),
                 health={"status": "healthy", "label": "Healthy", "summary": "All checks pass"},
                 exposure={"groups": {"unexpected": []}},
                 lid={"status": "safe"}, wake={"wifi": {"configured": True}})
    state["tailscale"].update(health_messages=[], devices=[
        {"hostname": "phone", "online": True, "is_self": False}])
    state["tailscale"]["serve"]["health"] = "healthy"
    return state, slow


def rust(state, slow, existing, now):
    payload = {"state": state, "slow": slow, "support": SUPPORT, "qrencode_available": True,
               "user": controller.USER, "home": str(controller.HOME),
               "activity_existing": existing, "now": now}
    result = subprocess.run([str(RUST), "phone-guide"], input=json.dumps(payload), text=True,
                            capture_output=True, check=True, timeout=5)
    assert result.stderr == "", result.stderr
    return json.loads(result.stdout)


def main():
    count = 0
    with tempfile.TemporaryDirectory(prefix="nyvorel-activity-parity-") as directory:
        base = Path(directory)
        controller.STATE_DIR = base
        controller.ACTIVITY_FILE = base / "activity.json"
        controller.STATE_DATA_LOCK = base / "state.lock"
        controller.RUST_PHONE_GUIDE_BIN = RUST
        controller.snapshot_pair_command_support = lambda: SUPPORT
        controller.exe = lambda name: "/usr/bin/qrencode" if name == "qrencode" else None
        now = 123456.75
        controller.time.time = lambda: now
        base_state, base_slow = full_baseline()

        def compare(state, slow, existing):
            nonlocal count
            controller.ACTIVITY_FILE.write_text(json.dumps(existing), encoding="utf-8")
            expected_events = controller._activity_state_unlocked(state)
            expected_activity = json.loads(controller.ACTIVITY_FILE.read_text(encoding="utf-8"))
            controller.ACTIVITY_FILE.write_text(json.dumps(existing), encoding="utf-8")
            actual = rust(state, slow, existing, now)
            assert actual["activity"] == expected_activity, {"expected": expected_activity, "actual": actual["activity"]}
            guide, events = controller.snapshot_phone_and_activity(state, slow)
            assert guide == controller.phone_guide(state, slow)
            assert events == expected_events
            assert json.loads(controller.ACTIVITY_FILE.read_text(encoding="utf-8")) == expected_activity
            count += 1

        compare(base_state, base_slow, {"previous": {}, "events": []})
        controller.ACTIVITY_FILE.write_text('{"previous": {}, "events": []}', encoding="utf-8")
        controller._activity_state_unlocked(base_state)
        previous = json.loads(controller.ACTIVITY_FILE.read_text(encoding="utf-8"))
        changes = (
            lambda s: s["services"]["lan_share"].update(running=False, ready=False),
            lambda s: s["services"]["wayvnc"].update(running=False, ready=False),
            lambda s: s["tailscale"].update(connected=False),
            lambda s: s["tailscale"]["serve"].update(configured=False, health="degraded", url=""),
            lambda s: s["tailscale"]["funnel"].update(verification="public", is_public=True),
            lambda s: s["tailscale"].update(health_messages=["Needs login"]),
            lambda s: s["tailscale"].update(devices=[{"hostname": "tablet", "online": True, "is_self": False}]),
            lambda s: s["health"].update(status="critical", label="Critical", summary="Unexpected exposure"),
            lambda s: s["exposure"]["groups"].update(unexpected=[{"endpoint": "0.0.0.0:5900"}]),
            lambda s: s["ssh_auth"].update(last_success_at=12355, last_success_ip="100.4.5.6", failure_count=3),
            lambda s: s["lid"].update(status="changed"),
            lambda s: s["wake"]["wifi"].update(configured=False),
        )
        for size in (1, 2):
            for group in itertools.combinations(changes, size):
                state = copy.deepcopy(base_state)
                for change in group:
                    change(state)
                compare(state, base_slow, previous)
        many = copy.deepcopy(previous)
        many["events"] = [{"id": str(i), "timestamp": 0, "kind": "old", "title": "old",
                           "detail": "old", "severity": "info"} for i in range(130)]
        compare(base_state, base_slow, many)
    print(f"Arch Remote activity and combined phone guide parity: {count} cases passed")


if __name__ == "__main__":
    main()
