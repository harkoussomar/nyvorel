//! Contextual sshd -T proof. A failed contextual check is never replaced by
//! context-free policy output.
use crate::process;
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::process::Command;
use std::time::Duration;

pub fn run(binary: &str, pkexec: &str, user: &str, privileged: bool) -> Value {
    if binary.is_empty() {
        return json!({"ok": false, "values": {}, "error": "sshd executable is unavailable", "source": "none"});
    }
    if privileged && pkexec.is_empty() {
        return json!({"ok": false, "values": {}, "error": "pkexec is unavailable", "source": "/usr/bin/sshd -T"});
    }
    let context = format!("user={user},host=localhost,addr=127.0.0.1");
    let source = format!(
        "{}{} -T -C {context}",
        if privileged { "pkexec " } else { "" },
        binary
    );
    let mut command = if privileged {
        Command::new(pkexec)
    } else {
        Command::new(binary)
    };
    if privileged {
        command.arg(binary);
    }
    command.args(["-T", "-C", &context]);
    let output = match process::run(
        &mut command,
        Duration::from_secs(if privileged { 20 } else { 7 }),
    ) {
        Ok(Some(output)) => output,
        Ok(None) | Err(_) => {
            return json!({"error": true, "message": "sshd proof command did not complete"})
        }
    };
    let mut values = BTreeMap::new();
    if output.status.success() {
        for line in output.stdout.lines() {
            let line = line.trim();
            if let Some(index) = line.find(char::is_whitespace) {
                let key = line[..index].to_lowercase();
                let value = line[index..].trim();
                if !value.is_empty() {
                    values.insert(key, value.to_string());
                }
            }
        }
    }
    let required = [
        "permitrootlogin",
        "pubkeyauthentication",
        "passwordauthentication",
        "kbdinteractiveauthentication",
    ];
    if output.status.success() && required.iter().all(|key| values.contains_key(*key)) {
        return json!({"ok": true, "values": values, "error": "", "source": source});
    }
    let raw = if output.stderr.is_empty() {
        output.stdout.trim()
    } else {
        output.stderr.trim()
    };
    let mut error = if raw.is_empty() {
        format!("exit {}", output.status.code().unwrap_or(127))
    } else {
        raw.chars().take(600).collect::<String>()
    };
    if !privileged && error.to_lowercase().contains("no hostkeys available") {
        error = "The unprivileged SSH check could not load host keys. ".to_string()
            + "Root-owned keys may be present but unreadable to this app. "
            + "Use Verify SSH to authorize a read-only policy check.";
    }
    json!({"ok": false, "values": {}, "error": error, "source": source})
}
