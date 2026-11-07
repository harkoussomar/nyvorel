//! Revoke a pending LAN Share credential when the installed CLI supports it.
use serde_json::{json, Value};
use std::io::{self, Read};

pub fn derive(input: &Value) -> Value {
    let binary = input["binary"].as_str().unwrap_or("");
    if input["cancel_supported"] != true || binary.is_empty() {
        return json!({"ok": true, "state": "cancelled", "backend_revoked": false,
            "message": "Pairing dismissed locally. The server credential will expire automatically or be invalidated by the next QR."});
    }
    let success = crate::pairing_create::revoke_command_succeeded(binary);
    if !success {
        return json!({"error": true, "ok": false, "state": "error",
            "message": "Could not revoke the pending pairing on LAN Share."});
    }
    json!({"ok": true, "state": "cancelled", "backend_revoked": true,
        "message": "Pairing cancelled and revoked"})
}

pub fn run() -> Value {
    let mut bytes = Vec::new();
    if io::stdin().take(8193).read_to_end(&mut bytes).is_err() || bytes.len() > 8192 {
        return json!({"error": true, "ok": false, "state": "error", "message": "Pairing cancel input is too large."});
    }
    match serde_json::from_slice::<Value>(&bytes) {
        Ok(input) => derive(&input),
        Err(_) => {
            json!({"error": true, "ok": false, "state": "error", "message": "Invalid pairing cancel input."})
        }
    }
}
