//! Recovery-aware one-shot actions. No Python controller participates.
use serde_json::{json, Value};
use std::thread;
use std::time::{Duration, Instant};

use crate::{
    activity, find_exe, listeners, lockdown_stop, native_snapshot, runtime_dir, services,
    ssh_policy, system_service_action, tailscale, user_service_action, Flock,
};

fn fail(message: impl AsRef<str>, state: &str) -> Value {
    json!({"error": true, "ok": false, "message": message.as_ref(), "state": state})
}

fn snapshot() -> Result<Value, Value> {
    let state = native_snapshot::run(false);
    if state.get("error") == Some(&Value::Bool(true)) {
        Err(state)
    } else {
        Ok(state)
    }
}

fn text(value: &Value) -> &str {
    value.as_str().unwrap_or("")
}

fn user_service(name: &str, action: &str) -> Value {
    if !matches!(name, "lan-share" | "wayvnc-remote")
        || !matches!(action, "start" | "stop" | "restart")
    {
        return fail("Unsupported user-service operation.", "invalid");
    }
    let label = if name == "lan-share" {
        "LAN Share"
    } else {
        "WayVNC"
    };
    let phase = format!("{action}ing");
    let mut stages = vec![json!({"phase": phase, "status": "running",
        "detail": format!("systemctl --user {action} {name}")})];
    if name == "lan-share" && matches!(action, "stop" | "restart") {
        activity::record(
            "pairing",
            "Private Share pairing cleared",
            "LAN Share stop/restart invalidates pending pairing credentials.",
            "info",
        );
    }
    let current = match snapshot() {
        Ok(state) => state,
        Err(_) => return fail("Could not verify current service state.", "failed"),
    };
    let Some(systemctl) = find_exe("systemctl") else {
        return fail("systemctl is unavailable.", "failed");
    };
    let input = json!({"name": name, "action": action, "systemctl": systemctl.to_string_lossy(),
        "hyprland_available": current["graphical"]["hyprland_available"],
        "wayland_display": current["graphical"]["wayland_display"],
        "tailscale_connected": current["tailscale"]["connected"],
        "vnc_security_ok": current["wayvnc_security"]["ok"],
        "vnc_security_reason": current["wayvnc_security"]["reason"]});
    let command = user_service_action::derive(&input);
    if command["ok"] != true {
        let message = text(&command["message"]);
        activity::record(
            "failure",
            &format!("{label} {action} failed"),
            message,
            "warning",
        );
        return json!({"error": true, "ok": false, "message": format!("{label}: {message}"),
            "state": "failed", "stages": stages});
    }
    stages.push(json!({"phase": "runtime", "status": "checking", "detail": "Waiting for systemd runtime state"}));
    thread::sleep(Duration::from_millis(350));
    let post = match snapshot() {
        Ok(state) => state,
        Err(_) => return fail("Could not verify service after action.", "failed"),
    };
    let key = if name == "lan-share" {
        "lan_share"
    } else {
        "wayvnc"
    };
    let domain = &post["services"][key];
    if action != "stop" {
        stages.push(json!({"phase": "listener", "status": "checking", "detail": "Verifying expected listener and policy"}));
        if domain["ready"] != true {
            let reason = text(&domain["readiness_reason"]);
            activity::record(
                "failure",
                &format!("{label} verification failed"),
                reason,
                "warning",
            );
            return json!({"error": true, "ok": false,
                "message": format!("{label}: running but not ready — {reason}"),
                "state": "running-not-ready", "service": domain, "stages": stages});
        }
        stages.push(
            json!({"phase": "ready", "status": "pass", "detail": domain["readiness_reason"]}),
        );
        activity::record(
            "operator",
            &format!("{label} {action} verified"),
            text(&domain["readiness_reason"]),
            "success",
        );
        return json!({"ok": true, "message": format!("{label}: Ready"), "state": "ready",
            "service": domain, "stages": stages});
    }
    stages.push(
        json!({"phase": "listener", "status": "checking", "detail": "Verifying listener removal"}),
    );
    if domain["listeners"]
        .as_array()
        .is_some_and(|items| !items.is_empty())
    {
        activity::record(
            "failure",
            &format!("{label} stop verification failed"),
            text(&domain["bind"]),
            "warning",
        );
        return json!({"error": true, "ok": false,
            "message": format!("{label}: service stopped but listener is still present"),
            "state": "stopped-listener-present", "service": domain, "stages": stages});
    }
    stages.push(json!({"phase": "stopped", "status": "pass", "detail": "Service inactive and expected listener absent"}));
    activity::record(
        "operator",
        &format!("{label} stopped"),
        "Service inactive; expected listener absent.",
        "info",
    );
    json!({"ok": true, "message": format!("{label}: stopped and verified"), "state": "stopped",
        "service": domain, "stages": stages})
}

fn system_service(name: &str, action: &str) -> Value {
    if name != "tailscaled" || !matches!(action, "start" | "restart") {
        return fail(
            "Only safe Tailscale start/restart is exposed here.",
            "invalid",
        );
    }
    let (Some(pkexec), Some(systemctl)) = (find_exe("pkexec"), find_exe("systemctl")) else {
        return fail("Polkit/systemctl is unavailable.", "failed");
    };
    let command = system_service_action::derive(&json!({"name": name, "action": action,
        "pkexec": pkexec.to_string_lossy(), "systemctl": systemctl.to_string_lossy()}));
    if command["ok"] != true {
        let message = text(&command["message"]);
        activity::record(
            "failure",
            &format!("Tailscale {action} failed"),
            message,
            "warning",
        );
        return fail(format!("Tailscale: {message}"), "failed");
    }
    let deadline = Instant::now() + Duration::from_secs(7);
    let mut last = Value::Null;
    loop {
        if let Ok(state) = snapshot() {
            last = state;
            if last["services"]["tailscaled"]["ready"] == true {
                activity::record(
                    "operator",
                    &format!("Tailscale {action} verified"),
                    "Daemon active and tailnet connected.",
                    "success",
                );
                return json!({"ok": true, "message": "Tailscale: connected and verified", "state": "ready",
                    "service": last["services"]["tailscaled"]});
            }
        }
        if Instant::now() >= deadline {
            break;
        }
        thread::sleep(Duration::from_millis(500));
    }
    let reason = last["services"]["tailscaled"]["readiness_reason"]
        .as_str()
        .unwrap_or("Tailnet did not become ready");
    fail(
        format!("Tailscale: running but not ready — {reason}"),
        "running-not-ready",
    )
}

fn lockdown() -> Value {
    let before = match snapshot() {
        Ok(state) => state,
        Err(_) => return fail("Could not verify recovery before lockdown.", "refused"),
    };
    if before["services"]["lan_share"]["running"] == true {
        activity::record(
            "pairing",
            "Private Share pairing cleared",
            "Lock Sharing stops LAN Share and invalidates pending pairing credentials.",
            "info",
        );
    }
    if before["services"]["sshd"]["running"] != true || before["tailscale"]["connected"] != true {
        return fail(
            "Lockdown refused: SSH + Tailscale recovery is not currently available.",
            "refused",
        );
    }
    let Some(systemctl) = find_exe("systemctl") else {
        return fail("systemctl is unavailable.", "failed");
    };
    let stopped = lockdown_stop::derive(&json!({"recovery_ok": true,
        "systemctl": systemctl.to_string_lossy(),
        "lan_share_running": before["services"]["lan_share"]["running"],
        "wayvnc_running": before["services"]["wayvnc"]["running"]}));
    if stopped["ok"] != true {
        return fail(
            "Could not stop sharing services; inspect state.",
            "partial-lockdown",
        );
    }
    let mut results = Vec::new();
    let mut failures = Vec::<String>::new();
    for (name, label, port) in [
        ("lan-share", "LAN Share", 8000),
        ("wayvnc-remote", "WayVNC", 5900),
    ] {
        let command = &stopped["results"][name];
        if command["ok"] != true {
            failures.push(format!("{label}: {}", text(&command["message"])));
            results.push(json!({"service": label, "status": "failed"}));
            continue;
        }
        let deadline = Instant::now() + Duration::from_millis(4500);
        let mut running = true;
        while Instant::now() < deadline {
            let state = services::run();
            let key = if name == "lan-share" {
                "lan_share"
            } else {
                "wayvnc"
            };
            running = state[key]["running"] == true;
            if !running {
                break;
            }
            thread::sleep(Duration::from_millis(250));
        }
        let status = tailscale::run();
        let listener_state = listeners::run(text(&status["ipv4"]), text(&status["ipv6"]));
        let relevant: Vec<Value> = listener_state
            .as_array()
            .into_iter()
            .flatten()
            .filter(|item| item["port"].as_i64() == Some(port))
            .cloned()
            .collect();
        if running || !relevant.is_empty() {
            failures.push(format!("{label}: runtime/listener still present"));
            results.push(json!({"service": label, "status": "failed", "listeners": relevant}));
        } else {
            results.push(json!({"service": label, "status": "stopped-verified"}));
        }
    }
    let post = match snapshot() {
        Ok(state) => state,
        Err(_) => {
            return fail(
                "Could not verify recovery after lockdown.",
                "partial-lockdown",
            )
        }
    };
    let recovery_ok =
        post["services"]["sshd"]["running"] == true && post["tailscale"]["connected"] == true;
    if !failures.is_empty() || !recovery_ok {
        let detail = if failures.is_empty() {
            "SSH/Tailscale recovery path changed unexpectedly".into()
        } else {
            failures.join("; ")
        };
        activity::record("lockdown", "Partial lockdown", &detail, "warning");
        return json!({"error": true, "ok": false, "message": format!("Partial lockdown — {detail}"),
            "state": "partial-lockdown", "results": results, "recovery_ok": recovery_ok});
    }
    activity::record(
        "lockdown",
        "Sharing locked",
        "LAN Share and WayVNC stopped and listeners verified absent; SSH + Tailscale preserved.",
        "success",
    );
    json!({"ok": true, "message": "Sharing locked and independently verified", "state": "locked",
        "results": results, "recovery_ok": true})
}

pub fn dispatch(kind: &str, args: &[String]) -> Value {
    let Ok(_lock) = Flock::try_acquire(&runtime_dir().join("action.lock")) else {
        return fail("Another Arch Remote action is already in progress.", "busy");
    };
    match (kind, args) {
        ("service", [name, action]) => user_service(name, action),
        ("system-service", [name, action]) => system_service(name, action),
        ("lockdown", []) => lockdown(),
        ("verify-ssh-effective", []) => ssh_policy::verify(),
        _ => fail("Unsupported operation.", "invalid"),
    }
}
