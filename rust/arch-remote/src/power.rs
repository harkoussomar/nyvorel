//! Wake-on-LAN, user linger, and lid-policy evidence for the slow snapshot.
use crate::process;
use regex::Regex;
use serde_json::{json, Value};
use std::fs;
use std::io::{self, Read};
use std::path::Path;
use std::process::Command;
use std::time::{Duration, UNIX_EPOCH};

const WOWLAN: &str = "/etc/NetworkManager/dispatcher.d/90-wowlan";
const LID_DROPIN: &str = "/etc/systemd/logind.conf.d/90-remote-access.conf";

fn text<'a>(value: &'a Value, key: &str) -> &'a str {
    value.get(key).and_then(Value::as_str).unwrap_or("")
}

fn capture_command(args: &[&str], timeout: u64) -> Option<process::Output> {
    let (binary, rest) = args.split_first()?;
    let mut command = Command::new(binary);
    command.args(rest);
    process::run(&mut command, Duration::from_secs(timeout))
        .ok()
        .flatten()
}

fn capture(pattern: &str, input: &str) -> String {
    Regex::new(pattern)
        .unwrap()
        .captures(input)
        .map(|captures| captures[1].to_string())
        .unwrap_or_default()
}

fn wake(interfaces: &[Value]) -> Value {
    let mut ethernet = json!({
        "interface_name": "", "mac": "", "supported": false, "enabled": false,
        "capability": "unknown", "configured": "unknown", "raw_supported": "",
        "raw_current": "", "tested": false, "test_status": "untested", "error": ""
    });
    let mut wifi = json!({
        "interface_name": "", "phy": "", "mac": "", "supported": false,
        "enabled": false, "capability": "unknown", "configured": "unknown",
        "persistent": Path::new(WOWLAN).is_file(), "tested": false,
        "test_status": "untested", "error": ""
    });
    let wired = interfaces
        .iter()
        .find(|item| {
            item["physical"] == true
                && item["wireless"] != true
                && item["loopback"] != true
                && item["tailscale"] != true
        })
        .or_else(|| {
            interfaces.iter().find(|item| {
                item["wireless"] != true && item["loopback"] != true && item["tailscale"] != true
            })
        });
    if let Some(chosen) = wired {
        ethernet["interface_name"] = json!(text(chosen, "name"));
        ethernet["mac"] = json!(text(chosen, "mac"));
    }
    if let Some(chosen) = interfaces.iter().find(|item| item["wireless"] == true) {
        wifi["interface_name"] = json!(text(chosen, "name"));
        wifi["mac"] = json!(text(chosen, "mac"));
    }
    let ethernet_name = text(&ethernet, "interface_name").to_string();
    if !ethernet_name.is_empty() {
        if let Some(result) = capture_command(&["ethtool", &ethernet_name], 5) {
            let support = capture(r"Supports Wake-on:\s*(\S+)", &result.stdout);
            let current = capture(r"Wake-on:\s*(\S+)", &result.stdout);
            ethernet["raw_supported"] = json!(support);
            ethernet["raw_current"] = json!(current);
            if !support.is_empty() {
                let enabled = support.contains('g');
                ethernet["capability"] = json!(if enabled { "supported" } else { "unsupported" });
                ethernet["supported"] = json!(enabled);
            }
            if !current.is_empty() {
                let enabled = current.contains('g');
                ethernet["configured"] = json!(if enabled { "enabled" } else { "disabled" });
                ethernet["enabled"] = json!(enabled);
            }
            if support.is_empty() && current.is_empty() {
                let message = if result.stderr.is_empty() {
                    result.stdout.trim()
                } else {
                    result.stderr.trim()
                };
                ethernet["error"] = json!(if message.is_empty() {
                    "ethtool did not expose Wake-on fields for the disconnected interface"
                        .to_string()
                } else {
                    message.chars().take(500).collect()
                });
            }
        }
    }
    let wifi_name = text(&wifi, "interface_name").to_string();
    if !wifi_name.is_empty() {
        let link = Path::new("/sys/class/net")
            .join(&wifi_name)
            .join("phy80211");
        let resolved = fs::canonicalize(&link).unwrap_or(link);
        let phy = resolved
            .file_name()
            .map(|name| name.to_string_lossy().into_owned())
            .unwrap_or_default();
        wifi["phy"] = json!(phy);
        if !phy.is_empty() {
            let info = capture_command(&["iw", "phy", &phy, "info"], 5);
            let show = capture_command(&["iw", "phy", &phy, "wowlan", "show"], 5);
            if info.is_some() || show.is_some() {
                let info_text = info
                    .as_ref()
                    .map(|output| output.stdout.to_lowercase())
                    .unwrap_or_default();
                let show_text = show
                    .as_ref()
                    .map(|output| output.stdout.to_lowercase())
                    .unwrap_or_default();
                if !info_text.is_empty() {
                    let supported = info_text.contains("magic packet");
                    wifi["capability"] = json!(if supported {
                        "supported"
                    } else {
                        "unsupported"
                    });
                    wifi["supported"] = json!(supported);
                }
                if !show_text.is_empty() {
                    let enabled = show_text.contains("magic packet");
                    wifi["configured"] = json!(if enabled { "enabled" } else { "disabled" });
                    wifi["enabled"] = json!(enabled);
                }
                if info_text.is_empty() && show_text.is_empty() {
                    let info_error = info
                        .as_ref()
                        .map(|output| output.stderr.as_str())
                        .unwrap_or("");
                    let show_error = show
                        .as_ref()
                        .map(|output| output.stderr.as_str())
                        .unwrap_or("");
                    let message = if info_error.is_empty() {
                        show_error.trim()
                    } else {
                        info_error.trim()
                    };
                    wifi["error"] = json!(message.chars().take(500).collect::<String>());
                }
            }
        }
    }
    json!({"ethernet": ethernet, "wifi": wifi, "dispatcher_path": WOWLAN})
}

fn linger(user: &str) -> Value {
    let mut command = Command::new("loginctl");
    command.args(["show-user", user, "-p", "Linger", "--value"]);
    let result = process::run(&mut command, Duration::from_secs(4));
    let Ok(result) = result else {
        return json!({"enabled": false, "value": "unknown", "source": "loginctl unavailable"});
    };
    let value = result
        .map(|output| output.stdout.trim().to_string())
        .unwrap_or_default();
    let value = if value.is_empty() {
        "unknown".into()
    } else {
        value
    };
    json!({"enabled": value.to_lowercase() == "yes", "value": value, "source": "loginctl show-user"})
}

fn config_words(path: &str) -> std::collections::HashMap<String, String> {
    let mut values = std::collections::HashMap::new();
    let Ok(content) = fs::read_to_string(path) else {
        return values;
    };
    for raw in content.lines() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') || line.starts_with('[') {
            continue;
        }
        if let Some((key, value)) = line.split_once('=') {
            values.insert(key.trim().to_lowercase(), value.trim().to_string());
        } else if let Some(index) = line.find(char::is_whitespace) {
            values.insert(
                line[..index].to_lowercase(),
                line[index..].trim().to_string(),
            );
        }
    }
    values
}

fn lid() -> Value {
    let exists = Path::new(LID_DROPIN).is_file();
    let configured = config_words(LID_DROPIN);
    let battery = configured
        .get("handlelidswitch")
        .map(String::as_str)
        .unwrap_or("unknown");
    let external = configured
        .get("handlelidswitchexternalpower")
        .map(String::as_str)
        .unwrap_or("unknown");
    let docked = configured
        .get("handlelidswitchdocked")
        .map(String::as_str)
        .unwrap_or("unknown");
    let mtime = fs::metadata(LID_DROPIN)
        .ok()
        .and_then(|meta| meta.modified().ok())
        .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
        .map(|time| time.as_secs_f64())
        .unwrap_or(0.0);
    let start_text = capture_command(
        &[
            "systemctl",
            "show",
            "systemd-logind.service",
            "--property=ActiveEnterTimestamp",
            "--value",
        ],
        4,
    )
    .map(|output| output.stdout.trim().to_string())
    .unwrap_or_default();
    let epoch = if start_text.is_empty() {
        0.0
    } else {
        capture_command(&["date", "-d", &start_text, "+%s"], 3)
            .and_then(|output| output.stdout.trim().parse::<f64>().ok())
            .unwrap_or(0.0)
    };
    let pending = mtime > 0.0 && epoch > 0.0 && mtime > epoch;
    let verified = exists && epoch > 0.0 && !pending;
    let status = if pending {
        "configured-pending-reboot"
    } else if exists {
        "configured"
    } else {
        "unavailable"
    };
    json!({"exists": exists, "path": LID_DROPIN, "battery": battery, "external_power": external,
        "docked": docked, "configured": {"battery": battery, "external_power": external, "docked": docked},
        "effective": {"verified": verified, "battery": if verified { battery } else { "unverified" },
            "external_power": if verified { external } else { "unverified" },
            "docked": if verified { docked } else { "unverified" },
            "source": "logind start timestamp compared with drop-in mtime"},
        "pending_reboot": pending, "status": status, "logind_started_at": start_text})
}

pub fn run() -> Value {
    let mut input = Vec::new();
    if io::stdin().take(1_048_577).read_to_end(&mut input).is_err() || input.len() > 1_048_576 {
        return json!({"error": true, "message": "Power input is too large"});
    }
    let Ok(Value::Array(interfaces)) = serde_json::from_slice::<Value>(&input) else {
        return json!({"error": true, "message": "Invalid power input"});
    };
    collect(&interfaces)
}

pub fn collect(interfaces: &[Value]) -> Value {
    let home = std::env::var("HOME").unwrap_or_default();
    let user = std::env::var("USER")
        .ok()
        .filter(|user| !user.is_empty())
        .unwrap_or_else(|| {
            Path::new(&home)
                .file_name()
                .map(|name| name.to_string_lossy().into_owned())
                .unwrap_or_default()
        });
    json!({"wake": wake(interfaces), "linger": linger(&user), "lid": lid()})
}
