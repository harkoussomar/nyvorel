//! Bounded systemd user-service action with an allowlist and runtime confirmation.
//! The caller owns the global action lock and performs the final listener/policy check.
use crate::process;
use serde_json::{json, Value};
use std::io::{self, Read};
use std::process::Command;
use std::thread;
use std::time::{Duration, Instant};

fn fail(message: impl AsRef<str>) -> Value {
    json!({"error": true, "ok": false, "message": message.as_ref()})
}

pub fn derive(input: &Value) -> Value {
    let name = input["name"].as_str().unwrap_or("");
    let action = input["action"].as_str().unwrap_or("");
    let systemctl = input["systemctl"].as_str().unwrap_or("");
    if !["lan-share", "wayvnc-remote"].contains(&name)
        || !["start", "stop", "restart"].contains(&action)
    {
        return fail("Unsupported user-service operation.");
    }
    if systemctl.is_empty() {
        return fail("systemctl is unavailable.");
    }
    if name == "wayvnc-remote" && ["start", "restart"].contains(&action) {
        if input["hyprland_available"] != true
            || input["wayland_display"].as_str().unwrap_or("").is_empty()
        {
            return fail("No active Wayland/Hyprland session was detected.");
        }
        if input["tailscale_connected"] != true {
            return fail("Tailscale is disconnected.");
        }
        if input["vnc_security_ok"] != true {
            return fail(format!(
                "WayVNC security profile is not verified: {}",
                input["vnc_security_reason"]
                    .as_str()
                    .filter(|text| !text.is_empty())
                    .unwrap_or("unknown")
            ));
        }
    }
    let result = process::run(
        Command::new(systemctl).args(["--user", action, name]),
        Duration::from_secs(12),
    );
    let Some(output) = result.ok().flatten() else {
        return fail(format!("{action} failed"));
    };
    if !output.status.success() {
        let detail = if !output.stderr.trim().is_empty() {
            output.stderr.trim()
        } else {
            output.stdout.trim()
        };
        return fail(if detail.is_empty() {
            format!("{action} failed")
        } else {
            detail.to_owned()
        });
    }
    let expected = action != "stop";
    let deadline = Instant::now() + Duration::from_millis(4500);
    let mut active_state = "unknown".to_owned();
    loop {
        let mut observed = false;
        let query = process::run(
            Command::new(systemctl).args([
                "--user",
                "show",
                name,
                "--no-pager",
                "--property=ActiveState",
            ]),
            Duration::from_secs(4),
        );
        if let Ok(Some(output)) = query {
            if output.status.success() {
                for line in output.stdout.lines() {
                    if let Some(value) = line.strip_prefix("ActiveState=") {
                        active_state = value.trim().to_owned();
                        observed = !active_state.is_empty();
                    }
                }
            }
        }
        if observed && (active_state == "active") == expected {
            break;
        }
        if Instant::now() >= deadline {
            return fail(format!(
                "systemctl returned success, but ActiveState={active_state}."
            ));
        }
        thread::sleep(Duration::from_millis(250));
    }
    json!({"ok": true, "active_state": active_state, "running": expected})
}

pub fn run() -> Value {
    let mut bytes = Vec::new();
    if io::stdin().take(16_385).read_to_end(&mut bytes).is_err() || bytes.len() > 16_384 {
        return fail("User-service action input is too large.");
    }
    match serde_json::from_slice::<Value>(&bytes) {
        Ok(input) => derive(&input),
        Err(_) => fail("Invalid user-service action input."),
    }
}
