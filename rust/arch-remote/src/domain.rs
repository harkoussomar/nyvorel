//! Derive service readiness from systemd, listeners, Tailscale and security proof.
use serde_json::{json, Value};
use std::io::{self, Read};

fn yes(value: &Value) -> bool {
    super::py_truthy(Some(value))
}

fn str_at<'a>(value: &'a Value, key: &str) -> &'a str {
    value.get(key).and_then(Value::as_str).unwrap_or("")
}

fn service_listeners(exposure: &Value, port: i64) -> Vec<Value> {
    exposure["listeners"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|item| item["port"].as_i64() == Some(port))
        .cloned()
        .collect()
}

fn bind(listeners: &[Value]) -> String {
    let joined = listeners
        .iter()
        .map(|item| str_at(item, "endpoint"))
        .collect::<Vec<_>>()
        .join(", ");
    if joined.is_empty() {
        "none".into()
    } else {
        joined
    }
}

fn owned(listeners: &[Value], main_pid: i64, names: &[&str]) -> (bool, String) {
    if listeners.is_empty() {
        return (false, "expected listener is absent".into());
    }
    if main_pid == 0 {
        return (false, "systemd MainPID is unavailable".into());
    }
    for item in listeners {
        let pid = item["pid"].as_i64().unwrap_or(0);
        let process = str_at(item, "process");
        if pid != main_pid {
            return (
                false,
                format!(
                    "listener PID {} does not match systemd MainPID {main_pid}",
                    if pid == 0 {
                        "unknown".into()
                    } else {
                        pid.to_string()
                    }
                ),
            );
        }
        if !names.is_empty() && !names.contains(&process) {
            return (
                false,
                format!(
                    "listener process {} is not an expected service process",
                    if process.is_empty() {
                        "unknown"
                    } else {
                        process
                    }
                ),
            );
        }
    }
    (
        true,
        "listener process identity matches systemd MainPID".into(),
    )
}

fn finish(
    mut service: Value,
    ready: bool,
    reachable: bool,
    reason: String,
    evidence: &[&str],
) -> Value {
    let running = yes(&service["running"]);
    let on_demand = service["expected_state"] == "on-demand";
    service["ready"] = json!(ready);
    service["reachable"] = json!(reachable);
    service["healthy"] = json!(if running { ready } else { on_demand });
    service["readiness"] = json!(if ready {
        "ready"
    } else if running {
        "running-not-ready"
    } else if on_demand {
        "expected-off"
    } else {
        "down"
    });
    service["readiness_reason"] = json!(reason);
    service["evidence_sources"] = json!(evidence);
    service["health"] = json!(if ready {
        "ready"
    } else if running {
        "degraded"
    } else if on_demand {
        "expected-inactive"
    } else {
        "degraded"
    });
    service
}

fn private_verified(tailscale: &Value) -> bool {
    let serve = &tailscale["serve"];
    let funnel = &tailscale["funnel"];
    yes(&serve["configured"])
        && serve["tailnet_only"] == true
        && serve["verification"] == "tailnet-only"
        && (funnel["verification"] == "off" || funnel["verification"] == "tailnet-only")
        && !yes(&funnel["is_public"])
}

pub fn compute(input: Value) -> Option<Value> {
    let services = input.get("services")?;
    let tailscale = input.get("tailscale")?;
    let exposure = input.get("exposure")?;
    let graphical = input.get("graphical")?;
    let ssh_policy = input.get("ssh")?;
    let security = input.get("wayvnc_security")?;

    let mut ssh = services.get("sshd")?.clone();
    let ssh_listeners = service_listeners(exposure, 22);
    ssh["listeners"] = json!(ssh_listeners);
    ssh["bind"] = json!(bind(&ssh_listeners));
    let ssh_running = yes(&ssh["running"]);
    let ssh_ready = ssh_running
        && !ssh_listeners.is_empty()
        && yes(&ssh_policy["effective_verified"])
        && yes(&ssh_policy["secure"]);
    let ssh_reason = if !ssh_running {
        "sshd is not running"
    } else if ssh_listeners.is_empty() {
        "sshd is running but no port 22 listener was detected"
    } else if !yes(&ssh_policy["effective_verified"]) {
        "running; effective SSH policy not independently verified"
    } else if !yes(&ssh_policy["secure"]) {
        "running; effective SSH policy does not match the hardened expectation"
    } else {
        "port 22 listening; effective key-only policy verified"
    };
    ssh = finish(
        ssh,
        ssh_ready,
        ssh_running && !ssh_listeners.is_empty(),
        ssh_reason.into(),
        &["systemd", "ss", "sshd -T"],
    );
    ssh["reachability"] = json!(if yes(&ssh["reachable"]) {
        "listener-detected"
    } else {
        "not-detected"
    });

    let mut tailscaled = services.get("tailscaled")?.clone();
    let ts_running = yes(&tailscaled["running"]);
    let connected = yes(&tailscale["connected"]);
    let ts_ready = ts_running && connected;
    let ts_reason = if ts_ready {
        "daemon active and tailnet connected"
    } else if ts_running {
        "daemon running but tailnet is not connected"
    } else {
        "tailscaled is not running"
    };
    tailscaled = finish(
        tailscaled,
        ts_ready,
        connected,
        ts_reason.into(),
        &["systemd", "tailscale status --json"],
    );
    tailscaled["reachability"] = json!(if connected {
        "tailnet-connected"
    } else {
        "disconnected"
    });

    let mut share = services.get("lan_share")?.clone();
    let share_listeners = service_listeners(exposure, 8000);
    share["listeners"] = json!(share_listeners);
    share["bind"] = json!(bind(&share_listeners));
    let share_running = yes(&share["running"]);
    let listener_ok = !share_listeners.is_empty()
        && share_listeners
            .iter()
            .all(|item| item["bind_scope"] == "loopback");
    let (owner_ok, owner_reason) = owned(
        &share_listeners,
        share["pid"].as_i64().unwrap_or(0),
        &["python3", "python", "lan-share"],
    );
    let share_ready = share_running && listener_ok && owner_ok;
    let share_reachable = share_ready
        && private_verified(tailscale)
        && yes(&tailscale["serve"]["upstream_reachable"]);
    let share_reason = if !share_running {
        "intentionally off".into()
    } else if !listener_ok {
        "running but expected 127.0.0.1:8000 listener is missing or unsafe".into()
    } else if !owner_ok {
        format!("loopback listener exists but process ownership is unverified — {owner_reason}")
    } else {
        "127.0.0.1:8000 and listener process identity verified".into()
    };
    share = finish(
        share,
        share_ready,
        share_reachable,
        share_reason,
        &["systemd --user", "ss process/PID", "Tailscale Serve/Funnel"],
    );
    share["reachability"] = json!(if share_reachable {
        "private-serve"
    } else if share_ready {
        "local-ready-route-offline"
    } else {
        "not-ready"
    });

    let mut wayvnc = services.get("wayvnc")?.clone();
    let wayvnc_listeners = service_listeners(exposure, 5900);
    wayvnc["listeners"] = json!(wayvnc_listeners);
    wayvnc["bind"] = json!(bind(&wayvnc_listeners));
    let graphical_ready =
        yes(&graphical["hyprland_available"]) && yes(&graphical["wayland_display"]);
    wayvnc["graphical_ready"] = json!(graphical_ready);
    let listener_ok = !wayvnc_listeners.is_empty()
        && wayvnc_listeners
            .iter()
            .all(|item| item["bind_scope"] == "tailnet");
    let (owner_ok, owner_reason) = owned(
        &wayvnc_listeners,
        wayvnc["pid"].as_i64().unwrap_or(0),
        &["wayvnc"],
    );
    let wayvnc_running = yes(&wayvnc["running"]);
    let transport_ready = wayvnc_running && graphical_ready && listener_ok && owner_ok && connected;
    let auth_ready = yes(&security["ok"]);
    let wayvnc_ready = transport_ready && auth_ready;
    wayvnc["transport_ready"] = json!(transport_ready);
    wayvnc["auth_ready"] = json!(auth_ready);
    wayvnc["auth_mode"] = json!(if str_at(security, "auth_mode").is_empty() {
        "unverified"
    } else {
        str_at(security, "auth_mode")
    });
    wayvnc["auth_username"] = json!(str_at(security, "username"));
    wayvnc["auth_summary"] = json!(if auth_ready {
        "TLS + password verified"
    } else {
        "Authentication policy unverified"
    });
    wayvnc["tailnet_acl_verification"] =
        json!(if str_at(security, "tailnet_acl_verification").is_empty() {
            "external-unverified"
        } else {
            str_at(security, "tailnet_acl_verification")
        });
    let wayvnc_reason = if !wayvnc_running {
        if auth_ready {
            "intentionally off; TLS/password authentication profile verified".into()
        } else {
            "intentionally off; authentication profile needs repair".into()
        }
    } else if !graphical_ready {
        "running but no active Wayland/Hyprland session is available".into()
    } else if !listener_ok {
        "running but expected Tailscale-only :5900 listener is missing".into()
    } else if !owner_ok {
        format!(
            "Tailscale-only listener exists but process ownership is unverified — {owner_reason}"
        )
    } else if !connected {
        "listener exists but Tailscale is disconnected".into()
    } else if !auth_ready {
        "private transport is verified but independent WayVNC authentication is not".into()
    } else {
        "Wayland, process-owned Tailscale :5900, and WayVNC TLS/password authentication verified"
            .into()
    };
    wayvnc = finish(
        wayvnc,
        wayvnc_ready,
        transport_ready,
        wayvnc_reason,
        &[
            "systemd --user",
            "Hyprland/Wayland",
            "ss process/PID",
            "Tailscale",
            "WayVNC TLS auth config",
        ],
    );
    wayvnc["reachability"] = json!(if wayvnc_ready {
        "tailnet-authenticated"
    } else if transport_ready {
        "tailnet-transport"
    } else {
        "not-ready"
    });

    Some(json!({"sshd": ssh, "tailscaled": tailscaled, "lan_share": share, "wayvnc": wayvnc}))
}

pub fn run() -> Value {
    let mut input = Vec::new();
    if io::stdin().take(1_048_577).read_to_end(&mut input).is_err() || input.len() > 1_048_576 {
        return json!({"error": true, "message": "Service-domain input is too large"});
    }
    match serde_json::from_slice::<Value>(&input)
        .ok()
        .and_then(compute)
    {
        Some(value) => value,
        None => json!({"error": true, "message": "Invalid service-domain input"}),
    }
}
