//! Allowlisted privileged Tailscale action. The controller owns polkit UI,
//! the operation lock, and post-action tailnet readiness verification.
use crate::process;
use serde_json::{json, Value};
use std::io::{self, Read};
use std::process::Command;
use std::time::Duration;

fn fail(message: impl AsRef<str>) -> Value {
    json!({"error": true, "ok": false, "message": message.as_ref()})
}

pub fn derive(input: &Value) -> Value {
    let name = input["name"].as_str().unwrap_or("");
    let action = input["action"].as_str().unwrap_or("");
    let pkexec = input["pkexec"].as_str().unwrap_or("");
    let systemctl = input["systemctl"].as_str().unwrap_or("");
    if name != "tailscaled" || !["start", "restart"].contains(&action) {
        return fail("Only safe Tailscale start/restart is exposed here.");
    }
    if pkexec.is_empty() || systemctl.is_empty() {
        return fail("Polkit/systemctl is unavailable.");
    }
    let result = process::run(
        Command::new(pkexec).args([systemctl, action, name]),
        Duration::from_secs(30),
    );
    let Some(output) = result.ok().flatten() else {
        return fail(format!("tailscaled {action} failed"));
    };
    if !output.status.success() {
        let detail = if !output.stderr.trim().is_empty() {
            output.stderr.trim()
        } else {
            output.stdout.trim()
        };
        return fail(if detail.is_empty() {
            format!("tailscaled {action} failed")
        } else {
            detail.to_owned()
        });
    }
    json!({"ok": true, "state": "command-succeeded"})
}

pub fn run() -> Value {
    let mut bytes = Vec::new();
    if io::stdin().take(16_385).read_to_end(&mut bytes).is_err() || bytes.len() > 16_384 {
        return fail("System-service action input is too large.");
    }
    match serde_json::from_slice::<Value>(&bytes) {
        Ok(input) => derive(&input),
        Err(_) => fail("Invalid system-service action input."),
    }
}
