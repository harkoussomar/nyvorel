//! One-shot network interface discovery for the slow snapshot.
use crate::process;
use serde_json::{json, Value};
use std::path::Path;
use std::process::Command;
use std::time::Duration;

fn display(value: &Value) -> String {
    match value {
        Value::String(value) => value.clone(),
        Value::Null => "None".to_string(),
        Value::Bool(true) => "True".to_string(),
        Value::Bool(false) => "False".to_string(),
        _ => value.to_string(),
    }
}

fn field(value: &Value, name: &str, default: &str) -> String {
    value
        .get(name)
        .filter(|item| super::py_truthy(Some(item)))
        .map(display)
        .unwrap_or_else(|| default.to_string())
}

pub fn run() -> Value {
    let mut command = Command::new("ip");
    command.args(["-j", "addr", "show"]);
    let Ok(Some(output)) = process::run(&mut command, Duration::from_secs(4)) else {
        return json!([]);
    };
    if !output.status.success() {
        return json!([]);
    }
    let Ok(Value::Array(items)) = serde_json::from_str::<Value>(&output.stdout) else {
        return json!([]);
    };
    let mut interfaces = Vec::new();
    for item in items {
        let name = field(&item, "ifname", "");
        if name.is_empty() {
            continue;
        }
        let addresses = item
            .get("addr_info")
            .and_then(Value::as_array)
            .map(|entries| {
                entries
                    .iter()
                    .filter_map(|entry| entry.get("local"))
                    .filter(|value| super::py_truthy(Some(value)))
                    .map(display)
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();
        let interface_dir = Path::new("/sys/class/net").join(&name);
        interfaces.push(json!({
            "name": name,
            "state": field(&item, "operstate", "UNKNOWN"),
            "mac": field(&item, "address", ""),
            "addresses": addresses,
            "wireless": interface_dir.join("wireless").exists(),
            "physical": interface_dir.join("device").exists(),
            "tailscale": name.starts_with("tailscale"),
            "loopback": name == "lo",
        }));
    }
    Value::Array(interfaces)
}
