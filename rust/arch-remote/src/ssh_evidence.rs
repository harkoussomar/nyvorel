//! Read-only recent SSH authentication and host-key fingerprint evidence.
use crate::process;
use regex::Regex;
use serde_json::{json, Value};
use std::path::Path;
use std::process::Command;
use std::time::Duration;

fn auth() -> Option<Value> {
    let mut base = json!({
        "checked_at": super::now(), "last_success_at": 0.0,
        "last_success_ip": "", "last_success_message": "", "failure_count": 0,
        "source": "journalctl -u sshd"
    });
    let mut command = Command::new("journalctl");
    command.args([
        "-u",
        "sshd",
        "--since",
        "24 hours ago",
        "-n",
        "240",
        "--no-pager",
        "-o",
        "json",
    ]);
    let output = match process::run(&mut command, Duration::from_secs(8)) {
        Err(_) => return Some(base),
        Ok(None) => return None,
        Ok(Some(output)) => output,
    };
    let pattern = Regex::new(r" from ([0-9a-fA-F:.]+) port ").unwrap();
    let mut success: Option<(f64, String, String)> = None;
    let mut failures = 0_u64;
    for raw in output.stdout.lines() {
        let Ok(Value::Object(item)) = serde_json::from_str::<Value>(raw) else {
            continue;
        };
        let message = item
            .get("MESSAGE")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string();
        let lower = message.to_lowercase();
        let timestamp = item
            .get("__REALTIME_TIMESTAMP")
            .and_then(|value| {
                value
                    .as_str()
                    .and_then(|text| text.parse::<i64>().ok())
                    .or_else(|| value.as_i64())
            })
            .map(|value| value as f64 / 1_000_000.0)
            .unwrap_or(0.0);
        if lower.contains("accepted publickey") {
            let ip = pattern
                .captures(&message)
                .map(|capture| capture[1].to_string())
                .unwrap_or_default();
            if success
                .as_ref()
                .is_none_or(|previous| timestamp > previous.0)
            {
                success = Some((timestamp, ip, message.clone()));
            }
        }
        if [
            "authentication failure",
            "failed password",
            "invalid user",
            "failed publickey",
        ]
        .iter()
        .any(|term| lower.contains(term))
        {
            failures += 1;
        }
    }
    if let Some((timestamp, ip, message)) = success {
        base["last_success_at"] = json!(timestamp);
        base["last_success_ip"] = json!(ip);
        base["last_success_message"] = json!(message.chars().take(500).collect::<String>());
    }
    base["failure_count"] = json!(failures);
    Some(base)
}

fn fingerprint(path: &str) -> Option<Value> {
    let empty = json!({"available": false, "algorithm": "", "fingerprint": "", "source": ""});
    if path.is_empty() || !Path::new(path).is_file() {
        return Some(empty);
    }
    let mut command = Command::new("ssh-keygen");
    command.args(["-lf", path, "-E", "sha256"]);
    let output = match process::run(&mut command, Duration::from_secs(4)) {
        Err(_) => return Some(empty),
        Ok(None) => return None,
        Ok(Some(output)) => output,
    };
    if !output.status.success() {
        return Some(empty);
    }
    let found = output
        .stdout
        .split_whitespace()
        .find(|part| part.starts_with("SHA256:"))
        .unwrap_or("");
    Some(
        json!({"available": !found.is_empty(), "algorithm": "ED25519", "fingerprint": found, "source": path}),
    )
}

pub fn run(path: &str) -> Value {
    match (auth(), fingerprint(path)) {
        (Some(auth), Some(fingerprint)) => json!({"auth": auth, "fingerprint": fingerprint}),
        _ => json!({"error": true, "message": "SSH evidence command timed out"}),
    }
}
