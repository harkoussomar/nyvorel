//! Tailscale daemon status, excluding Serve/Funnel exposure classification.
use serde_json::{json, Value};
use std::process::Command;
use std::time::Duration;

use crate::process;

fn base(available: bool) -> Value {
    json!({"available": available, "active": false, "running": false,
        "connected": false, "backend_state": "unavailable", "hostname": "",
        "dns_name": "", "ipv4": "", "ipv6": "", "magic_dns": false,
        "devices": [], "phone": null, "health": "unavailable", "health_messages": []})
}

fn truthy(value: Option<&Value>) -> bool {
    match value {
        None | Some(Value::Null | Value::Bool(false)) => false,
        Some(Value::Number(n)) => n.as_f64().unwrap_or(0.0) != 0.0,
        Some(Value::String(s)) => !s.is_empty(),
        Some(Value::Array(a)) => !a.is_empty(),
        Some(Value::Object(o)) => !o.is_empty(),
        _ => true,
    }
}

fn text(value: Option<&Value>) -> String {
    match value {
        Some(Value::String(s)) => s.clone(),
        Some(Value::Number(n)) => n.to_string(),
        Some(Value::Bool(true)) => "True".into(),
        Some(Value::Bool(false)) => "False".into(),
        _ => String::new(),
    }
}

fn first<'a>(values: impl IntoIterator<Item = Option<&'a Value>>) -> Option<&'a Value> {
    values.into_iter().flatten().find(|item| truthy(Some(item)))
}

fn peer(peer: &Value, self_peer: bool) -> Value {
    let addresses = first([peer.get("TailscaleIPs"), peer.get("Addresses")])
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
        .iter()
        .map(|value| text(Some(value)))
        .collect::<Vec<_>>();
    let hostname = text(first([
        peer.get("HostName"),
        peer.get("ComputedName"),
        peer.get("DNSName"),
    ]));
    let hostname = if hostname.is_empty() {
        "Unknown".to_string()
    } else {
        hostname
    };
    let dns_name = text(peer.get("DNSName")).trim_end_matches('.').to_string();
    let os = text(peer.get("OS"));
    let os = if os.is_empty() {
        "unknown".to_string()
    } else {
        os
    };
    let online = peer
        .get("Online")
        .map(|value| truthy(Some(value)))
        .unwrap_or(self_peer);
    let active = peer
        .get("Active")
        .map(|value| truthy(Some(value)))
        .unwrap_or(online);
    json!({"hostname": hostname, "dns_name": dns_name, "os": os, "addresses": addresses,
        "online": online, "active": active, "last_seen": text(peer.get("LastSeen")),
        "last_handshake": text(peer.get("LastHandshake")), "is_self": self_peer})
}

fn hostname() -> String {
    let mut buffer = [0_u8; 256];
    if unsafe { libc::gethostname(buffer.as_mut_ptr().cast(), buffer.len()) } != 0 {
        return String::new();
    }
    let end = buffer
        .iter()
        .position(|byte| *byte == 0)
        .unwrap_or(buffer.len());
    String::from_utf8_lossy(&buffer[..end]).into_owned()
}

pub fn run() -> Value {
    let mut command = Command::new("tailscale");
    command.args(["status", "--json"]);
    let result = process::run(&mut command, Duration::from_secs(6));
    let Ok(output) = result else {
        return base(false);
    };
    let mut state = base(true);
    let payload = match output {
        Some(output) if output.status.success() => {
            match serde_json::from_str::<Value>(&output.stdout) {
                Ok(Value::Object(payload)) => payload,
                Ok(_) => return state,
                Err(_) => serde_json::Map::new(),
            }
        }
        _ => serde_json::Map::new(),
    };
    let self_peer = payload.get("Self").filter(|value| truthy(Some(value)));
    let empty = json!({});
    let self_peer = self_peer.unwrap_or(&empty);
    let ips = first([self_peer.get("TailscaleIPs"), payload.get("TailscaleIPs")])
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let backend = text(first([payload.get("BackendState")])).to_string();
    let backend = if backend.is_empty() {
        "unknown".to_string()
    } else {
        backend
    };
    let connected = backend == "Running";
    let dns_name = text(self_peer.get("DNSName"))
        .trim_end_matches('.')
        .to_string();
    let mut devices = Vec::new();
    if truthy(Some(self_peer)) {
        devices.push(peer(self_peer, true));
    }
    match payload.get("Peer") {
        Some(Value::Object(peers)) => {
            for item in peers.values() {
                if item.is_object() {
                    devices.push(peer(item, false));
                }
            }
        }
        Some(Value::Array(peers)) => {
            for item in peers {
                if item.is_object() {
                    devices.push(peer(item, false));
                }
            }
        }
        _ => {}
    }
    let phone = devices
        .iter()
        .find(|device| {
            let searchable = format!(
                "{} {} {}",
                device["hostname"].as_str().unwrap_or(""),
                device["dns_name"].as_str().unwrap_or(""),
                device["os"].as_str().unwrap_or("")
            )
            .to_lowercase();
            searchable.contains("android") || searchable.contains("s22")
        })
        .cloned();
    let health_messages = match payload.get("Health").filter(|value| truthy(Some(value))) {
        Some(Value::Array(items)) => items
            .iter()
            .map(|item| text(Some(item)))
            .collect::<Vec<_>>(),
        Some(value) => vec![text(Some(value))],
        _ => Vec::new(),
    };
    let magic_dns = truthy(first([
        payload.get("MagicDNSSuffix"),
        payload
            .get("CurrentTailnet")
            .and_then(|tailnet| tailnet.get("MagicDNSEnabled")),
    ]));
    let self_name = text(self_peer.get("HostName"));
    state["active"] = json!(connected);
    state["running"] = json!(connected);
    state["connected"] = json!(connected);
    state["backend_state"] = json!(backend);
    state["hostname"] = json!(if self_name.is_empty() {
        hostname()
    } else {
        self_name
    });
    state["dns_name"] = json!(dns_name);
    state["ipv4"] = json!(ips
        .iter()
        .map(|value| text(Some(value)))
        .find(|value| value.contains('.'))
        .unwrap_or_default());
    state["ipv6"] = json!(ips
        .iter()
        .map(|value| text(Some(value)))
        .find(|value| value.contains(':'))
        .unwrap_or_default());
    state["magic_dns"] = json!(magic_dns);
    state["devices"] = json!(devices);
    state["phone"] = json!(phone);
    state["health"] = json!(if !health_messages.is_empty() {
        "degraded"
    } else if connected {
        "healthy"
    } else {
        "degraded"
    });
    state["health_messages"] = json!(health_messages);
    state
}
