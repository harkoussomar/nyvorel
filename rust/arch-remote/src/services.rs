//! Read-only systemd service collector used by the live snapshot.
use serde_json::{json, Value};
use std::collections::HashMap;
use std::process::Command;
use std::thread;
use std::time::Duration;

use crate::process;

const PROPERTIES: &str = "--property=LoadState,ActiveState,SubState,UnitFileState,MainPID,NRestarts,ActiveEnterTimestamp,FragmentPath,MemoryCurrent,CPUUsageNSec,Result,ExecMainStatus";

fn base(name: &str, scope: &str, expected_running: bool) -> Value {
    json!({"name": name, "scope": scope, "loaded": false, "configured": false,
        "active": false, "running": false, "active_state": "unknown", "sub_state": "unknown",
        "enabled_state": "unknown", "enabled": false, "boot_enabled": false,
        "expected_running": expected_running,
        "expected_state": if expected_running { "running" } else { "on-demand" },
        "status": "unavailable", "health": "unavailable", "pid": 0, "restarts": 0,
        "started_at": "", "fragment_path": "", "memory_bytes": 0, "memory": "—",
        "cpu_time": "—", "result": "unknown", "exec_main_status": "unknown"})
}

fn parse_values(output: &str) -> HashMap<String, String> {
    output
        .lines()
        .filter_map(|line| line.split_once('='))
        .map(|(key, value)| (key.trim().to_string(), value.trim().to_string()))
        .collect()
}

fn integer(values: &HashMap<String, String>, key: &str) -> i64 {
    values
        .get(key)
        .and_then(|value| value.parse().ok())
        .unwrap_or(0)
}

fn unsigned(values: &HashMap<String, String>, key: &str) -> u64 {
    values
        .get(key)
        .and_then(|value| value.parse().ok())
        .unwrap_or(0)
}

fn wide_integer(values: &HashMap<String, String>, key: &str) -> i128 {
    values
        .get(key)
        .and_then(|value| value.parse().ok())
        .unwrap_or(0)
}

fn human_bytes(bytes: i128) -> String {
    let mut value = bytes as f64;
    for suffix in ["B", "KB", "MB", "GB", "TB"] {
        if value < 1024.0 || suffix == "TB" {
            return if suffix == "B" || suffix == "KB" {
                format!("{value:.0} {suffix}")
            } else {
                format!("{value:.1} {suffix}")
            };
        }
        value /= 1024.0;
    }
    "0 B".into()
}

fn human_seconds(nanoseconds: u64) -> String {
    let seconds = nanoseconds / 1_000_000_000;
    if seconds < 60 {
        return format!("{seconds}s");
    }
    let minutes = seconds / 60;
    let second = seconds % 60;
    if minutes < 60 {
        return format!("{minutes}m {second:02}s");
    }
    let hours = minutes / 60;
    let minute = minutes % 60;
    if hours < 24 {
        return format!("{hours}h {minute:02}m");
    }
    format!("{}d {}h", hours / 24, hours % 24)
}

fn service_state(name: &'static str, scope: &'static str, expected_running: bool) -> Value {
    let fallback = base(name, scope, expected_running);
    let mut command = Command::new("systemctl");
    if scope == "user" {
        command.arg("--user");
    }
    command.args(["show", name, "--no-pager", PROPERTIES]);
    let Ok(Some(output)) = process::run(&mut command, Duration::from_secs(4)) else {
        return fallback;
    };
    if !output.status.success() && output.stdout.trim().is_empty() {
        return fallback;
    }
    let values = parse_values(&output.stdout);
    let get = |key: &str, fallback: &str| {
        values
            .get(key)
            .map(String::as_str)
            .unwrap_or(fallback)
            .to_string()
    };
    let loaded = get("LoadState", "") == "loaded";
    let active_state = get("ActiveState", "unknown");
    let running = active_state == "active";
    let enabled_state = get("UnitFileState", "unknown");
    let boot_enabled =
        ["enabled", "enabled-runtime", "linked", "static"].contains(&enabled_state.as_str());
    let pid = integer(&values, "MainPID");
    let restarts = integer(&values, "NRestarts");
    let memory_bytes = wide_integer(&values, "MemoryCurrent");
    let cpu_ns = unsigned(&values, "CPUUsageNSec");
    let health = if !loaded {
        "unavailable"
    } else if expected_running && !running {
        "degraded"
    } else if !expected_running && !running {
        "expected-inactive"
    } else {
        "healthy"
    };
    let status = if !loaded {
        "unavailable"
    } else if running {
        "running"
    } else if active_state == "failed" {
        "failed"
    } else {
        "inactive"
    };
    json!({"name": name, "scope": scope, "loaded": loaded, "configured": loaded,
        "active": running, "running": running, "active_state": active_state,
        "sub_state": get("SubState", "unknown"), "enabled_state": enabled_state,
        "enabled": boot_enabled, "boot_enabled": boot_enabled,
        "expected_running": expected_running,
        "expected_state": if expected_running { "running" } else { "on-demand" },
        "status": status, "health": health, "pid": pid, "restarts": restarts,
        "started_at": get("ActiveEnterTimestamp", ""), "fragment_path": get("FragmentPath", ""),
        "memory_bytes": memory_bytes, "memory": if memory_bytes > 0 { human_bytes(memory_bytes) } else { "—".into() },
        "cpu_time": if cpu_ns > 0 { human_seconds(cpu_ns) } else { "—".into() },
        "result": get("Result", "unknown"), "exec_main_status": get("ExecMainStatus", "unknown")})
}

pub fn run() -> Value {
    let handles = [
        thread::spawn(|| service_state("sshd", "system", true)),
        thread::spawn(|| service_state("tailscaled", "system", true)),
        thread::spawn(|| service_state("lan-share", "user", false)),
        thread::spawn(|| service_state("wayvnc-remote", "user", false)),
    ];
    let mut values = Vec::new();
    for (index, handle) in handles.into_iter().enumerate() {
        let (name, scope, expected) = match index {
            0 => ("sshd", "system", true),
            1 => ("tailscaled", "system", true),
            2 => ("lan-share", "user", false),
            _ => ("wayvnc-remote", "user", false),
        };
        values.push(
            handle
                .join()
                .unwrap_or_else(|_| base(name, scope, expected)),
        );
    }
    json!({"sshd": values.remove(0), "tailscaled": values.remove(0),
        "lan_share": values.remove(0), "wayvnc": values.remove(0)})
}
