//! Small user-facing controller commands with explicit input validation.
use serde_json::{json, Value};
use std::io::Write;
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};
use url::Url;

use crate::{activity, find_exe, home, native_snapshot, reference};

fn fail(message: &str) -> Value {
    json!({"error": true, "ok": false, "message": message})
}

pub fn reference() -> Value {
    let state = native_snapshot::run(false);
    if state.get("error") == Some(&Value::Bool(true)) {
        return fail("Could not load current Arch Remote state.");
    }
    let user = state["host"]["user"].as_str().unwrap_or("");
    reference::derive(&json!({"state": state, "user": user, "home": home().to_string_lossy()}))
        .unwrap_or_else(|| fail("Could not build a safe Arch Remote reference."))
}

pub fn record_event(args: &[String]) -> Value {
    let [kind, title, detail, rest @ ..] = args else {
        return fail("Missing activity fields.");
    };
    let severity = rest.first().map(String::as_str).unwrap_or("info");
    if kind.len() > 80
        || title.len() > 300
        || detail.len() > 2000
        || !matches!(severity, "info" | "success" | "warning" | "error")
    {
        return fail("Invalid activity fields.");
    }
    if !activity::record(kind, title, detail, severity) {
        return fail("Could not record activity.");
    }
    json!({"ok": true, "message": "Activity recorded"})
}

pub fn copy(value: &str) -> Value {
    if value.len() > 2_097_152 {
        return fail("Clipboard text is too large.");
    }
    let Some(binary) = find_exe("wl-copy") else {
        return fail("wl-copy is unavailable.");
    };
    let mut child = match Command::new(binary)
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
    {
        Ok(child) => child,
        Err(_) => return fail("Clipboard copy failed."),
    };
    if child
        .stdin
        .take()
        .is_none_or(|mut stdin| stdin.write_all(value.as_bytes()).is_err())
    {
        let _ = child.kill();
        let _ = child.wait();
        return fail("Clipboard copy failed.");
    }
    let deadline = Instant::now() + Duration::from_secs(4);
    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                return if status.success() {
                    json!({"ok": true, "message": "Copied to clipboard"})
                } else {
                    fail("Clipboard copy failed.")
                }
            }
            Ok(None) if Instant::now() < deadline => thread::sleep(Duration::from_millis(10)),
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                return fail("Clipboard copy failed.");
            }
        }
    }
}

pub fn open_url(value: &str) -> Value {
    let Ok(url) = Url::parse(value) else {
        return fail("Only HTTP(S) URLs can be opened.");
    };
    if !matches!(url.scheme(), "http" | "https") || url.host_str().is_none() {
        return fail("Only HTTP(S) URLs can be opened.");
    }
    let Some(binary) = find_exe("xdg-open") else {
        return fail("xdg-open is unavailable.");
    };
    match Command::new(binary)
        .arg(value)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
    {
        Ok(_) => json!({"ok": true, "message": "Opened URL"}),
        Err(_) => fail("Could not open URL."),
    }
}
