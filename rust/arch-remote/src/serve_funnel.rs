//! Read Tailscale Serve and Funnel status without changing exposure policy.
//! Human-readable Funnel status remains authoritative for public/private state.
use crate::process;
use regex::Regex;
use serde_json::{json, Value};
use std::process::Command;
use std::time::Duration;

fn command(binary: &str, args: &[&str]) -> (bool, String) {
    let mut command = Command::new(binary);
    command.args(args);
    match process::run(&mut command, Duration::from_secs(5)) {
        Ok(Some(output)) => {
            let raw = if output.stdout.is_empty() {
                output.stderr
            } else {
                output.stdout
            };
            (output.status.success(), raw)
        }
        _ => (false, String::new()),
    }
}

fn raw(value: &str) -> String {
    value.trim().chars().take(5000).collect()
}

fn first_proxy(payload: &Value) -> (String, String, String) {
    let Some(web) = payload.get("Web").and_then(Value::as_object) else {
        return (String::new(), String::new(), String::new());
    };
    for (host_port, config) in web {
        let Some(handlers) = config.get("Handlers").and_then(Value::as_object) else {
            continue;
        };
        for (route, handler) in handlers {
            let Some(handler) = handler.as_object() else {
                continue;
            };
            let proxy = ["Proxy", "proxy"]
                .iter()
                .filter_map(|key| handler.get(*key))
                .find(|value| super::py_truthy(Some(value)));
            if let Some(proxy) = proxy {
                let host = host_port.split(':').next().unwrap_or("");
                let proxy = match proxy {
                    Value::String(value) => value.clone(),
                    other => other.to_string(),
                };
                return (host.to_string(), route.to_string(), proxy);
            }
        }
    }
    (String::new(), String::new(), String::new())
}

fn serve(binary: &str) -> Value {
    let mut state = json!({
        "available": !binary.is_empty(), "active": false, "configured": false,
        "url": "", "host": "", "route_path": "", "upstream": "",
        "upstream_tested": false, "upstream_reachable": false, "upstream_status": 0,
        "tailnet_only": false, "is_public": false, "verification": "unavailable",
        "health": "inactive", "source": "tailscale serve status", "raw": ""
    });
    if binary.is_empty() {
        return state;
    }
    let (json_ok, json_text) = command(binary, &["serve", "status", "--json"]);
    let (_, text) = command(binary, &["serve", "status"]);
    let text = text.trim().to_string();
    state["raw"] = json!(raw(&text));
    let payload = if json_ok {
        serde_json::from_str::<Value>(&json_text).unwrap_or(Value::Null)
    } else {
        Value::Null
    };
    let (host, route, upstream) = first_proxy(&payload);
    if !host.is_empty() {
        state["host"] = json!(host);
        state["url"] = json!(format!("https://{host}"));
    } else {
        let pattern = Regex::new(r"https://([A-Za-z0-9._-]+)(?::\d+)?/?").unwrap();
        if let Some(captures) = pattern.captures(&text) {
            state["host"] = json!(&captures[1]);
            state["url"] = json!(captures[0].trim_end_matches('/'));
        }
    }
    if !route.is_empty() {
        state["route_path"] = json!(if route.starts_with('/') {
            route
        } else {
            format!("/{route}")
        });
    }
    if !upstream.is_empty() {
        state["upstream"] = json!(upstream);
    } else if !text.is_empty() {
        let pattern = Regex::new(r"proxy\s+(https?://[^\s]+)").unwrap();
        if let Some(captures) = pattern.captures(&text) {
            state["upstream"] = json!(&captures[1]);
        }
    }
    let mut configured = !state["url"].as_str().unwrap_or("").is_empty()
        || !state["upstream"].as_str().unwrap_or("").is_empty()
        || super::py_truthy(payload.get("TCP"))
        || super::py_truthy(payload.get("Web"));
    let lower = text.to_lowercase();
    if lower.contains("no serve config") || lower.contains("not configured") {
        configured = false;
    }
    state["configured"] = json!(configured);
    state["active"] = json!(configured);
    if !configured {
        state["verification"] = json!("off");
    } else if lower.contains("tailnet only") {
        state["tailnet_only"] = json!(true);
        state["verification"] = json!("tailnet-only");
    } else if lower.contains("available on the internet") || lower.contains("funnel on") {
        state["is_public"] = json!(true);
        state["verification"] = json!("public");
    } else {
        state["verification"] = json!("unknown");
    }
    state["health"] = json!(if !configured {
        "inactive"
    } else if state["verification"] == "public" {
        "critical"
    } else if state["verification"] != "tailnet-only" {
        "unknown"
    } else {
        "healthy"
    });
    state
}

fn funnel(binary: &str) -> Value {
    let mut state = json!({
        "available": !binary.is_empty(), "active": false, "configured": false,
        "is_public": false, "url": "", "verification": "unavailable",
        "health": "unavailable",
        "source": "tailscale funnel status (text is authoritative for public/private classification)",
        "raw": ""
    });
    if binary.is_empty() {
        return state;
    }
    let (_, text) = command(binary, &["funnel", "status"]);
    let text = text.trim().to_string();
    state["raw"] = json!(raw(&text));
    let lower = text.to_lowercase();
    let pattern = Regex::new(r"https://[A-Za-z0-9._-]+(?::\d+)?/?").unwrap();
    if let Some(found) = pattern.find(&text) {
        state["url"] = json!(found.as_str().trim_end_matches('/'));
    }
    if lower.contains("tailnet only") {
        state["verification"] = json!("tailnet-only");
        state["health"] = json!("healthy");
    } else if lower.contains("available on the internet")
        || lower.contains("funnel on")
        || lower.contains("public")
    {
        state["active"] = json!(true);
        state["configured"] = json!(true);
        state["is_public"] = json!(true);
        state["verification"] = json!("public");
        state["health"] = json!("critical");
    } else if lower.contains("no funnel") || lower.contains("not configured") {
        state["verification"] = json!("off");
        state["health"] = json!("healthy");
    } else {
        state["verification"] = json!("unknown");
        state["health"] = json!("unknown");
    }
    state
}

pub fn run(binary: &str) -> Value {
    json!({"serve": serve(binary), "funnel": funnel(binary)})
}
