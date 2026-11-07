//! Pure activity change detection. The controller retains locking and atomic persistence.
use serde_json::{json, Value};
use std::path::PathBuf;

use crate::{atomic_json, home, now, read_json, Flock};

pub fn record(kind: &str, title: &str, detail: &str, severity: &str) -> bool {
    let directory: PathBuf = home().join(".local/state/nyvorel/arch-remote");
    let Ok(_lock) = Flock::acquire(&directory.join(".state.lock")) else {
        return false;
    };
    let path = directory.join("activity.json");
    let mut payload = read_json(&path).unwrap_or_else(|| json!({"previous": {}, "events": []}));
    let mut events = payload["events"].as_array().cloned().unwrap_or_default();
    let timestamp = now();
    let id = format!("{}-{kind}-{}", (timestamp * 1000.0) as u64, events.len());
    events.insert(
        0,
        json!({"id": id, "timestamp": timestamp, "kind": kind,
        "title": title, "detail": detail, "severity": severity}),
    );
    events.truncate(120);
    payload["events"] = json!(events);
    atomic_json(&path, &payload).is_ok()
}
use std::collections::BTreeSet;

fn yes(value: &Value) -> bool {
    crate::py_truthy(Some(value))
}
fn text(value: &Value) -> &str {
    value.as_str().unwrap_or("")
}
fn value_or<'a>(value: &'a Value, fallback: &'a Value) -> &'a Value {
    if yes(value) {
        value
    } else {
        fallback
    }
}
fn names(items: &Value, field: &str, filter: impl Fn(&Value) -> bool) -> Vec<String> {
    let mut out: Vec<String> = items
        .as_array()
        .into_iter()
        .flatten()
        .filter(|item| filter(item))
        .map(|item| text(&item[field]).to_owned())
        .collect();
    out.sort();
    out
}
fn old_new(previous: &Value, compact: &Value, key: &str) -> (BTreeSet<String>, BTreeSet<String>) {
    let array = |object: &Value| -> BTreeSet<String> {
        object[key]
            .as_array()
            .into_iter()
            .flatten()
            .map(|item| text(item).to_owned())
            .collect()
    };
    (array(previous), array(compact))
}
fn py_str(value: &Value) -> String {
    match value {
        Value::Bool(true) => "True".into(),
        Value::Bool(false) => "False".into(),
        Value::Null => "None".into(),
        Value::String(s) => s.clone(),
        _ => value.to_string(),
    }
}

pub fn derive(current: &Value, existing: &Value, now: f64) -> Value {
    let previous = &existing["previous"];
    let mut events = existing["events"].as_array().cloned().unwrap_or_default();
    let auth = &current["ssh_auth"];
    let compact = json!({
        "lan_share": yes(&current["services"]["lan_share"]["running"]),
        "lan_share_ready": yes(&current["services"]["lan_share"]["ready"]),
        "wayvnc": yes(&current["services"]["wayvnc"]["running"]),
        "wayvnc_ready": yes(&current["services"]["wayvnc"]["ready"]),
        "tailscale": yes(&current["tailscale"]["connected"]),
        "serve": yes(&current["tailscale"]["serve"]["configured"]),
        "serve_health": current["tailscale"]["serve"]["health"],
        "serve_url": current["tailscale"]["serve"]["url"],
        "funnel": current["tailscale"]["funnel"]["verification"],
        "health": current["health"]["status"],
        "ts_health": current["tailscale"]["health_messages"].as_array().cloned().unwrap_or_default(),
        "devices": names(&current["tailscale"]["devices"], "hostname", |device| yes(&device["online"]) && !yes(&device["is_self"])),
        "unexpected": names(&current["exposure"]["groups"]["unexpected"], "endpoint", |_| true),
        "ssh_success": auth["last_success_at"].as_f64().unwrap_or(0.0),
        "ssh_success_ip": text(&auth["last_success_ip"]),
        "ssh_failures": auth["failure_count"].as_i64().unwrap_or(0),
        "lid": current["lid"]["status"],
        "wifi_wake": current["wake"]["wifi"]["configured"],
    });
    let had_no_events = events.is_empty();
    let mut add = |kind: &str, title: String, detail: String, severity: &str| {
        let id = format!("{}-{kind}-{}", (now * 1000.0) as i64, events.len());
        events.insert(
            0,
            json!({"id": id, "timestamp": now, "kind": kind,
            "title": title, "detail": detail, "severity": severity}),
        );
    };
    if yes(previous) {
        for (key, label) in [
            ("lan_share", "LAN Share"),
            ("wayvnc", "Remote desktop"),
            ("tailscale", "Tailscale"),
        ] {
            if previous.get(key) != compact.get(key) {
                let started = yes(&compact[key]);
                add(
                    "service",
                    format!("{label} {}", if started { "started" } else { "stopped" }),
                    "Observed from the canonical runtime snapshot.".into(),
                    if started { "success" } else { "info" },
                );
            }
        }
        for (key, label) in [
            ("lan_share_ready", "LAN Share"),
            ("wayvnc_ready", "Remote desktop"),
        ] {
            if previous.get(key) != compact.get(key) && yes(&compact[key]) {
                add(
                    "verification",
                    format!("{label} readiness verified"),
                    "Runtime and expected listener evidence now agree.".into(),
                    "success",
                );
            }
        }
        if ["serve", "serve_health", "serve_url"]
            .iter()
            .any(|key| previous.get(*key) != compact.get(*key))
        {
            add(
                "serve",
                "Tailscale Serve state changed".into(),
                format!(
                    "{} · {}",
                    value_or(&compact["serve_url"], &json!("No URL"))
                        .as_str()
                        .unwrap_or("No URL"),
                    text(&compact["serve_health"])
                ),
                if compact["serve_health"] == "degraded" {
                    "warning"
                } else {
                    "info"
                },
            );
        }
        if previous.get("funnel") != compact.get("funnel") {
            add(
                "exposure",
                "Funnel exposure state changed".into(),
                text(&compact["funnel"]).into(),
                if compact["funnel"] == "public" {
                    "critical"
                } else {
                    "info"
                },
            );
        }
        let (old_devices, new_devices) = old_new(previous, &compact, "devices");
        for name in new_devices.difference(&old_devices) {
            add(
                "device",
                format!("{name} became online"),
                "Tailnet peer is online.".into(),
                "success",
            );
        }
        for name in old_devices.difference(&new_devices) {
            add(
                "device",
                format!("{name} went offline"),
                "Tailnet peer is offline.".into(),
                "info",
            );
        }
        if previous.get("health") != compact.get("health") {
            add(
                "audit",
                format!(
                    "Remote-access health changed to {}",
                    text(&current["health"]["label"])
                ),
                text(&current["health"]["summary"]).into(),
                if ["degraded", "critical"].contains(&text(&compact["health"])) {
                    "warning"
                } else {
                    "success"
                },
            );
        }
        let (old_unexpected, new_unexpected) = old_new(previous, &compact, "unexpected");
        for endpoint in new_unexpected.difference(&old_unexpected) {
            add(
                "exposure",
                "Unexpected listener exposure detected".into(),
                endpoint.clone(),
                "critical",
            );
        }
        if previous.get("ts_health") != compact.get("ts_health") {
            if let Some(messages) = compact["ts_health"]
                .as_array()
                .filter(|items| !items.is_empty())
            {
                add(
                    "tailscale",
                    "Tailscale health warning appeared".into(),
                    messages.iter().map(text).collect::<Vec<_>>().join("; "),
                    "warning",
                );
            } else if yes(&previous["ts_health"]) {
                add(
                    "tailscale",
                    "Tailscale health warning recovered".into(),
                    "Current Tailscale health is clear.".into(),
                    "success",
                );
            }
        }
        if yes(&compact["ssh_success"]) && previous.get("ssh_success") != compact.get("ssh_success")
        {
            let phone = &current["tailscale"]["phone"];
            let from_phone = phone["addresses"]
                .as_array()
                .is_some_and(|ips| ips.iter().any(|ip| ip == &compact["ssh_success_ip"]));
            let title = if from_phone {
                format!(
                    "SSH key login from {}",
                    value_or(&phone["hostname"], &json!("phone"))
                        .as_str()
                        .unwrap_or("phone")
                )
            } else {
                "SSH key login observed".into()
            };
            add(
                "auth",
                title,
                value_or(
                    &compact["ssh_success_ip"],
                    &json!("Source address unavailable"),
                )
                .as_str()
                .unwrap_or("Source address unavailable")
                .into(),
                "success",
            );
        }
        let previous_failures = previous["ssh_failures"].as_i64().unwrap_or(0);
        let current_failures = compact["ssh_failures"].as_i64().unwrap_or(0);
        if current_failures > previous_failures {
            add(
                "auth",
                "SSH authentication failures observed".into(),
                format!(
                    "{} new failure(s) in the bounded 24-hour evidence window.",
                    current_failures - previous_failures
                ),
                "warning",
            );
        }
        if previous.get("lid") != compact.get("lid") {
            add(
                "configuration",
                "Lid policy state changed".into(),
                py_str(&compact["lid"]),
                "info",
            );
        }
        if previous.get("wifi_wake") != compact.get("wifi_wake") {
            add(
                "configuration",
                "WoWLAN configuration changed".into(),
                py_str(&compact["wifi_wake"]),
                "info",
            );
        }
    } else if had_no_events {
        add(
            "system",
            "Arch Remote monitoring initialized".into(),
            "Canonical runtime state store created.".into(),
            "info",
        );
    }
    events.truncate(120);
    json!({"previous": compact, "events": events})
}
