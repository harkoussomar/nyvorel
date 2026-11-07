//! Execute only the two user-service stops authorized by lockdown preflight.
use serde_json::{json, Value};
use std::io::{self, Read};
use std::process::Command;
use std::time::Duration;

use crate::process;

pub fn derive(input: &Value) -> Value {
    if input["recovery_ok"] != true {
        return json!({"error": true, "ok": false, "message": "Lockdown refused: SSH + Tailscale recovery is not currently available."});
    }
    let Some(systemctl) = input["systemctl"]
        .as_str()
        .filter(|path| path.starts_with('/'))
    else {
        return json!({"error": true, "ok": false, "message": "systemctl is unavailable."});
    };
    let mut results = serde_json::Map::new();
    for (name, field) in [
        ("lan-share", "lan_share_running"),
        ("wayvnc-remote", "wayvnc_running"),
    ] {
        if input[field] != true {
            results.insert(name.into(), json!({"ok": true, "skipped": true}));
            continue;
        }
        let result = process::run(
            Command::new(systemctl).args(["--user", "stop", name]),
            Duration::from_secs(12),
        );
        let value = match result {
            Ok(Some(output)) if output.status.success() => json!({"ok": true, "skipped": false}),
            Ok(Some(output)) => {
                let detail = if output.stderr.trim().is_empty() {
                    output.stdout.trim()
                } else {
                    output.stderr.trim()
                };
                json!({"ok": false, "message": if detail.is_empty() { "stop failed" } else { detail }})
            }
            _ => json!({"ok": false, "message": "stop failed"}),
        };
        results.insert(name.into(), value);
    }
    json!({"ok": true, "results": results})
}

pub fn run() -> Value {
    let mut bytes = Vec::new();
    if io::stdin().take(16_385).read_to_end(&mut bytes).is_err() || bytes.len() > 16_384 {
        return json!({"error": true, "ok": false, "message": "Lockdown input is too large."});
    }
    let Ok(input) = serde_json::from_slice::<Value>(&bytes) else {
        return json!({"error": true, "ok": false, "message": "Invalid lockdown input."});
    };
    derive(&input)
}
