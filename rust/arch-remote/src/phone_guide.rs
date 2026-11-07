//! Derive the phone setup model from a supplied snapshot. No system calls.
use serde_json::{json, Value};
use std::io::{self, Read};

fn yes(value: &Value) -> bool {
    crate::py_truthy(Some(value))
}

fn text(value: &Value) -> &str {
    value.as_str().unwrap_or("")
}

fn chosen<'a>(values: impl IntoIterator<Item = &'a Value>) -> &'a str {
    values
        .into_iter()
        .map(text)
        .find(|value| !value.is_empty())
        .unwrap_or("")
}

pub fn derive(input: &Value) -> Value {
    let state = &input["state"];
    let slow = &input["slow"];
    let support = &input["support"];
    let tailscale = &state["tailscale"];
    let services = &state["services"];
    let sshd = &services["sshd"];
    let wayvnc = &services["wayvnc"];
    let share = &services["lan_share"];
    let serve = &tailscale["serve"];
    let host = chosen([
        &tailscale["dns_name"],
        &tailscale["hostname"],
        &state["host"]["hostname"],
    ]);
    let user = text(&input["user"]);
    let root_path = text(&input["home"]);
    let phone = &tailscale["phone"];
    let phone_present = yes(phone);
    let phone_addresses = phone["addresses"].as_array();
    let auth = &slow["ssh_auth"];
    let success_ip = text(&auth["last_success_ip"]);
    let ssh_observed = !success_ip.is_empty()
        && phone_addresses
            .is_some_and(|addresses| addresses.iter().any(|ip| text(ip) == success_ip));
    let (ssh_state, ssh_confidence) = if ssh_observed {
        ("observed", "observed")
    } else if yes(&slow["ssh"]["authorized_keys_exists"]) && yes(&sshd["ready"]) {
        ("configured", "configured-not-tested")
    } else {
        ("unavailable", "unverified")
    };
    let avnc_state = if yes(&wayvnc["ready"]) {
        "ready"
    } else if yes(&wayvnc["running"]) {
        "degraded"
    } else if !yes(&wayvnc["graphical_ready"]) {
        "unavailable"
    } else {
        "off"
    };
    let pairing = crate::pairing_readiness::derive(input);
    let safe_share_url = text(&pairing["serve_url"]);
    let private_verified = yes(&pairing["checks"]["private_exposure_verified"]);
    let share_available = yes(&share["reachable"]) && !safe_share_url.is_empty();
    let vnc_start_available = yes(&wayvnc["graphical_ready"])
        && yes(&tailscale["connected"])
        && yes(&wayvnc["auth_ready"]);
    let unavailable_reason = if vnc_start_available {
        ""
    } else if !yes(&wayvnc["graphical_ready"]) {
        "No active Wayland session"
    } else if !yes(&tailscale["connected"]) {
        "Tailscale is disconnected"
    } else {
        "WayVNC authentication profile needs repair"
    };
    let tail_state = if phone_present {
        if yes(&phone["online"]) {
            "connected"
        } else {
            "offline"
        }
    } else {
        "not-detected"
    };
    let ssh_config = format!(
        "Host arch-pc\n    HostName {host}\n    User {user}\n    IdentityFile ~/.ssh/id_ed25519\n    IdentitiesOnly yes\n    ServerAliveInterval 30\n    ServerAliveCountMax 3"
    );
    let fingerprint = slow["ssh_host_fingerprint"].clone();
    json!({
        "host": host, "user": user, "ssh_command": "ssh arch-pc",
        "ssh_config": ssh_config, "commands": "ssh arch-pc\narchctl status\narchctl shell",
        "fingerprint": fingerprint, "device": if phone_present { phone.clone() } else { json!({}) },
        "readiness": {
            "tailscale": {"state": tail_state, "confidence": if phone_present { "observed" } else { "unverified" }},
            "ssh": {"state": ssh_state, "confidence": ssh_confidence,
                    "last_observed_at": auth.get("last_success_at").cloned().unwrap_or(json!(0))},
            "sftp": {"state": if yes(&sshd["ready"]) { "available" } else { "unavailable" },
                     "confidence": if yes(&sshd["ready"]) { "inferred-from-ssh" } else { "unverified" }},
            "avnc": {"state": avnc_state, "confidence": if yes(&wayvnc["ready"]) { "verified" } else { "configured" }},
            "share": {"state": if share_available { "available" } else { "unavailable" },
                      "confidence": if share_available { "verified" } else { "configured" }},
        },
        "sftp": {"host": host, "port": 22, "user": user, "root_path": root_path,
                 "fingerprint": slow["ssh_host_fingerprint"]["fingerprint"]},
        "vnc": {"endpoint": if host.is_empty() { String::new() } else { format!("{host}:5900") },
                "service_active": wayvnc["running"], "running": wayvnc["running"],
                "ready": wayvnc.get("ready").cloned().unwrap_or(json!(false)),
                "transport_ready": wayvnc.get("transport_ready").cloned().unwrap_or(json!(false)),
                "auth_ready": wayvnc.get("auth_ready").cloned().unwrap_or(json!(false)),
                "auth_mode": wayvnc.get("auth_mode").cloned().unwrap_or(json!("unverified")),
                "auth_username": wayvnc.get("auth_username").cloned().unwrap_or(json!("")),
                "state": avnc_state,
                "readiness_reason": wayvnc.get("readiness_reason").cloned().unwrap_or(json!("")),
                "start_available": vnc_start_available, "unavailable_reason": unavailable_reason},
        "share": {"url": safe_share_url, "service_active": share["running"],
                  "running": share["running"], "ready": share.get("ready").cloned().unwrap_or(json!(false)),
                  "configured": serve["configured"], "upstream_reachable": serve["upstream_reachable"],
                  "is_private": private_verified, "tailnet_only": private_verified,
                  "privacy_verification": if private_verified { "verified-private" } else { "unverified" },
                  "pairing_available": pairing["available"], "pairing_reason": pairing["reason"],
                  "pairing_checks": pairing["checks"], "pairing_cancel_supported": support["cancel_supported"]},
    })
}

pub fn run() -> Value {
    let mut input = Vec::new();
    if io::stdin().take(2_097_152).read_to_end(&mut input).is_err() {
        return json!({"error": true, "message": "Could not read phone-guide evidence"});
    }
    match serde_json::from_slice::<Value>(&input) {
        Ok(input) if input.get("activity_existing").is_some() => {
            let guide = derive(&input);
            let activity = crate::activity::derive(
                &input["state"],
                &input["activity_existing"],
                input["now"].as_f64().unwrap_or(0.0),
            );
            json!({"phone_guide": guide, "activity": activity})
        }
        Ok(input) => derive(&input),
        Err(_) => json!({"error": true, "message": "Invalid phone-guide evidence"}),
    }
}
