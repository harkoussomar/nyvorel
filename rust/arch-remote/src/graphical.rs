//! Read-only Wayland/Hyprland availability for remote-desktop readiness.
use crate::process;
use serde_json::{json, Value};
use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use std::time::Duration;

pub fn run() -> Value {
    let runtime = env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(format!("/run/user/{}", unsafe { libc::getuid() })));
    let mut sockets = Vec::new();
    if let Ok(entries) = fs::read_dir(runtime) {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            if name.starts_with("wayland-") && entry.path().exists() {
                sockets.push(name);
            }
        }
    }
    sockets.sort();
    let mut command = Command::new("hyprctl");
    command.args(["-j", "monitors"]);
    let available = match process::run(&mut command, Duration::from_secs(4)) {
        Ok(Some(output)) => {
            matches!(serde_json::from_str::<Value>(&output.stdout), Ok(Value::Array(items)) if !items.is_empty())
        }
        _ => false,
    };
    let wayland = env::var("WAYLAND_DISPLAY")
        .ok()
        .filter(|value| !value.is_empty())
        .or_else(|| sockets.first().cloned())
        .unwrap_or_default();
    json!({"hyprland_available": available, "wayland_display": wayland, "wayland_sockets": sockets})
}
