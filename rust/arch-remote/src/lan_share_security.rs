//! Validate LAN Share's published security contract without minting pairing credentials.
use crate::process;
use serde_json::{json, Value};
use std::process::Command;
use std::time::Duration;

fn unavailable(reason: &str) -> Value {
    json!({"ok": false, "security_revision": "", "reason": reason})
}

fn required(payload: &Value) -> bool {
    let failures = payload["pin_rate_limit"]["client_max_failures"]
        .as_i64()
        .or_else(|| {
            payload["pin_rate_limit"]["client_max_failures"]
                .as_str()?
                .parse()
                .ok()
        })
        .unwrap_or(0);
    let protected = payload["protected_paths"].as_array();
    payload["ok"].as_bool().unwrap_or(false)
        && payload["security_revision"] == "2.1-phase1b1"
        && payload["session_required"] == true
        && payload["query_token_auth"] == false
        && payload["pairing_requires_verified_private_serve"] == true
        && failures >= 3
        && protected.is_some_and(|paths| {
            paths.contains(&json!(".ssh")) && paths.contains(&json!(".config"))
        })
}

pub fn run(binary: &str) -> Value {
    if binary.is_empty() {
        return unavailable("LAN Share is not installed.");
    }
    let output = process::run(
        Command::new(binary).args(["security", "--json"]),
        Duration::from_secs(4),
    );
    let Ok(Some(output)) = output else {
        return unavailable("LAN Share security contract is unavailable.");
    };
    if !output.status.success() {
        return unavailable("LAN Share security contract is unavailable.");
    }
    let Ok(mut payload) = serde_json::from_str::<Value>(&output.stdout) else {
        return unavailable("LAN Share security contract returned invalid JSON.");
    };
    let ok = required(&payload);
    let Some(values) = payload.as_object_mut() else {
        return unavailable("LAN Share security contract returned invalid JSON.");
    };
    values.insert("ok".into(), json!(ok));
    values.insert(
        "reason".into(),
        json!(if ok {
            "LAN Share Phase 1B.1 security contract verified."
        } else {
            "LAN Share security contract is incomplete."
        }),
    );
    payload
}
