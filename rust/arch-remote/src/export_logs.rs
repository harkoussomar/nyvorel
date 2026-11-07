//! One-shot redacted log export. No worker or memory remains after the command exits.
use serde_json::{json, Value};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::PathBuf;

use crate::{home, logs};

pub fn run(args: &[String]) -> Value {
    let payload = logs::run(args);
    if payload.get("ok") != Some(&Value::Bool(true)) {
        return payload;
    }
    let Some(service) = payload.get("service").and_then(Value::as_str) else {
        return json!({"error": true, "message": "Missing log source."});
    };
    // logs::run has already checked the allowlist. Check it again before using
    // the service as a filename component.
    if !matches!(service, "sshd" | "tailscaled" | "lan-share" | "wayvnc") {
        return json!({"error": true, "message": "Unknown log source."});
    }
    let raw = payload.get("raw").and_then(Value::as_str).unwrap_or("");
    let directory = home().join(".local/state/nyvorel/arch-remote/exports");
    if fs::create_dir_all(&directory).is_err()
        || fs::set_permissions(&directory, fs::Permissions::from_mode(0o700)).is_err()
    {
        return json!({"error": true, "message": "Could not create private log export directory."});
    }
    let time = unsafe { libc::time(std::ptr::null_mut()) };
    let mut tm = unsafe { std::mem::zeroed::<libc::tm>() };
    if unsafe { libc::localtime_r(&time, &mut tm) }.is_null() {
        return json!({"error": true, "message": "Could not determine export time."});
    }
    let stamp = format!(
        "{:04}{:02}{:02}-{:02}{:02}{:02}",
        tm.tm_year + 1900,
        tm.tm_mon + 1,
        tm.tm_mday,
        tm.tm_hour,
        tm.tm_min,
        tm.tm_sec
    );
    let mut selected: Option<(PathBuf, std::fs::File)> = None;
    for suffix in 0..100 {
        let name = if suffix == 0 {
            format!("{service}-{stamp}.log")
        } else {
            format!("{service}-{stamp}-{suffix}.log")
        };
        let path = directory.join(name);
        match OpenOptions::new()
            .create_new(true)
            .write(true)
            .mode(0o600)
            .open(&path)
        {
            Ok(file) => {
                selected = Some((path, file));
                break;
            }
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(_) => {
                return json!({"error": true, "message": "Could not create private log export."})
            }
        }
    }
    let Some((path, mut file)) = selected else {
        return json!({"error": true, "message": "Too many log exports in this second."});
    };
    if file
        .write_all(raw.as_bytes())
        .and_then(|_| file.write_all(b"\n"))
        .and_then(|_| file.sync_all())
        .is_err()
    {
        let _ = fs::remove_file(&path);
        return json!({"error": true, "message": "Could not finish log export."});
    }
    let path_text = path.to_string_lossy();
    json!({"ok": true, "message": format!("Exported logs to {path_text}"), "path": path_text})
}
