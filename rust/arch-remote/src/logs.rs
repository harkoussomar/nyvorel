//! Bounded, redacted journal inspection. No service action or export occurs here.
use regex::Regex;
use serde_json::{json, Value};
use std::process::Command;
use std::sync::LazyLock;
use std::time::Duration;

use crate::process;

static PAIR_FIELD: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r#"(?i)(pair_url\s*[=:]\s*["']?)[^\s"']+"#).expect("fixed pair field regex")
});
static PAIR_URL: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r#"(?i)https://[^\s"']+/pair#t=[^\s"']+"#).expect("fixed pair URL regex")
});
static PAIR_FRAGMENT: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)(#t=)[A-Za-z0-9._~%+\-/=]+").expect("fixed pair fragment regex")
});

fn redact(value: &str) -> String {
    let field = PAIR_FIELD.replace_all(value, "${1}[REDACTED]");
    let url = PAIR_URL.replace_all(&field, "[REDACTED PAIRING URL]");
    PAIR_FRAGMENT
        .replace_all(&url, "${1}[REDACTED]")
        .into_owned()
}

fn value_text(value: Option<&Value>) -> String {
    match value {
        Some(Value::String(s)) => s.clone(),
        Some(Value::Number(n)) => n.to_string(),
        Some(Value::Bool(true)) => "True".into(),
        Some(Value::Bool(false)) => "False".into(),
        _ => String::new(),
    }
}

fn priority_name(value: &str) -> &'static str {
    match value.parse::<i32>() {
        Ok(n) if n <= 3 => "ERROR",
        Ok(4) => "WARN",
        Ok(5 | 6) => "INFO",
        Ok(_) => "DEBUG",
        Err(_) => "INFO",
    }
}

fn source(service: &str) -> Option<(&'static str, bool)> {
    match service {
        "sshd" => Some(("sshd", false)),
        "tailscaled" => Some(("tailscaled", false)),
        "lan-share" => Some(("lan-share", true)),
        "wayvnc" => Some(("wayvnc-remote", true)),
        _ => None,
    }
}

fn journal(unit: &str, user: bool, since: &str) -> Result<String, ()> {
    let mut command = Command::new("journalctl");
    if user {
        command.arg("--user");
    }
    command.args([
        "-u",
        unit,
        "--since",
        since,
        "-n",
        "240",
        "--no-pager",
        "-o",
        "json",
    ]);
    Ok(process::run(&mut command, Duration::from_secs(10))
        .map_err(|_| ())?
        .map(|output| output.stdout)
        .unwrap_or_default())
}

fn timestamp_text(timestamp: f64) -> String {
    let epoch = timestamp as libc::time_t;
    let mut tm = unsafe { std::mem::zeroed::<libc::tm>() };
    if unsafe { libc::localtime_r(&epoch, &mut tm) }.is_null() {
        return "00:00:00".into();
    }
    format!("{:02}:{:02}:{:02}", tm.tm_hour, tm.tm_min, tm.tm_sec)
}

fn count(haystack: &str, needle: &str) -> usize {
    haystack.matches(needle).count()
}

fn issue(
    known: &mut Vec<Value>,
    kind: (&str, &str, &str),
    n: usize,
    detail: String,
    recovery: &str,
    action: &str,
) {
    if n > 0 {
        let (id, severity, title) = kind;
        known.push(
            json!({"id": id, "severity": severity, "title": title, "count": n,
            "detail": detail, "recovery": recovery, "action": action}),
        );
    }
}

fn issues(service: &str, window: &str, raw: &str) -> Vec<Value> {
    let lower = raw.to_lowercase();
    let mut known = Vec::new();
    match service {
        "wayvnc" => {
            let n = count(&lower, "failed to capture cursor");
            issue(
                &mut known,
                (
                    "wayvnc-cursor-capture",
                    "warning",
                    "WayVNC lost cursor capture",
                ),
                n,
                format!("{n} occurrence(s) in {window}."),
                "Normal recovery: restart WayVNC.",
                "restart-wayvnc",
            );
            let n = count(&lower, "address already in use") + count(&lower, "failed to bind");
            issue(
                &mut known,
                ("wayvnc-bind", "warning", "WayVNC bind failure"),
                n,
                format!("{n} bind-related occurrence(s)."),
                "Inspect port 5900 and restart after the conflict is resolved.",
                "none",
            );
        }
        "sshd" => {
            let n: usize = [
                "failed password",
                "authentication failure",
                "invalid user",
                "failed publickey",
            ]
            .iter()
            .map(|term| count(&lower, term))
            .sum();
            issue(
                &mut known,
                (
                    "ssh-auth-failures",
                    if n >= 3 { "warning" } else { "info" },
                    "SSH authentication failures",
                ),
                n,
                format!("{n} authentication failure(s) in {window}."),
                "Review source addresses and keep key-only authentication enabled.",
                "none",
            );
        }
        "tailscaled" => {
            let n = count(&lower, "dns-forward-failing");
            if n > 0 {
                let recovered = lower.contains("health(warnable=dns-forward-failing): ok");
                known.push(json!({"id": "tailscale-dns-forward", "severity": if recovered { "info" } else { "warning" },
                    "title": "Tailscale DNS forwarding warning", "count": n,
                    "detail": format!("{n} health transition(s) in {window}."),
                    "recovery": if recovered { "Recovered in-window" } else { "Check configured DNS and local connectivity." },
                    "action": "none"}));
            }
            let n = count(&lower, "home derp changing") + count(&lower, "home is now derp");
            issue(
                &mut known,
                ("tailscale-derp", "info", "Tailscale relay path changed"),
                n,
                format!("{n} DERP path transition(s)."),
                "Informational unless persistent connectivity is degraded.",
                "none",
            );
            let n = count(&lower, "auth expired")
                + count(&lower, "authentication expired")
                + count(&lower, "needslogin");
            issue(
                &mut known,
                (
                    "tailscale-auth",
                    "warning",
                    "Tailscale authentication needs attention",
                ),
                n,
                format!("{n} authentication-related occurrence(s)."),
                "Re-authenticate Tailscale.",
                "none",
            );
        }
        "lan-share" => {
            let n = count(&lower, "traceback");
            issue(
                &mut known,
                ("lan-share-traceback", "warning", "LAN Share service crash"),
                n,
                format!("{n} Python traceback(s)."),
                "Restart LAN Share and verify localhost:8000.",
                "restart-share",
            );
            let n = count(&lower, "address already in use") + count(&lower, "failed to bind");
            issue(
                &mut known,
                ("lan-share-bind", "warning", "LAN Share bind failure"),
                n,
                format!("{n} bind-related occurrence(s)."),
                "Inspect localhost:8000 and restart after the conflict is resolved.",
                "none",
            );
            let n = count(&lower, "connection refused") + count(&lower, "upstream");
            issue(
                &mut known,
                ("lan-share-upstream", "info", "LAN Share upstream warning"),
                n,
                format!("{n} upstream-related occurrence(s)."),
                "Verify the local share process and Tailscale Serve route.",
                "none",
            );
        }
        _ => {}
    }
    known
}

pub fn run(args: &[String]) -> Value {
    let Some(service) = args.first() else {
        return json!({"error": true, "message": "list index out of range"});
    };
    let Some((unit, user)) = source(service) else {
        return json!({"error": true, "message": "Unknown log source."});
    };
    let errors_alias = args.get(1).map(String::as_str) == Some("--errors");
    let severity = if errors_alias {
        "warning"
    } else {
        args.get(1).map(String::as_str).unwrap_or("all")
    };
    let window = if errors_alias {
        "1h"
    } else {
        args.get(2).map(String::as_str).unwrap_or("1h")
    };
    let search = if errors_alias {
        ""
    } else {
        args.get(3).map(String::as_str).unwrap_or("")
    };
    let since = match window {
        "15m" => "15 minutes ago",
        "6h" => "6 hours ago",
        "24h" => "24 hours ago",
        _ => "1 hour ago",
    };
    let output = match journal(unit, user, since) {
        Ok(text) => text,
        Err(_) => return json!({"error": true, "message": "journalctl is unavailable."}),
    };
    let mut entries = Vec::new();
    let search_lower = search.to_lowercase();
    for line in output.lines() {
        let Ok(Value::Object(item)) = serde_json::from_str::<Value>(line) else {
            continue;
        };
        let message = redact(&value_text(item.get("MESSAGE")));
        let priority = value_text(item.get("PRIORITY"));
        let level = priority_name(if priority.is_empty() { "6" } else { &priority });
        let timestamp = value_text(item.get("__REALTIME_TIMESTAMP"))
            .parse::<i64>()
            .unwrap_or(0) as f64
            / 1_000_000.0;
        if severity == "warning" && level != "WARN" && level != "ERROR" {
            continue;
        }
        if severity == "error" && level != "ERROR" {
            continue;
        }
        if !search_lower.is_empty() && !message.to_lowercase().contains(&search_lower) {
            continue;
        }
        let lower = message.to_lowercase();
        let auth = service == "sshd"
            && [
                "accepted publickey",
                "authentication failure",
                "failed password",
                "invalid user",
                "failed publickey",
            ]
            .iter()
            .any(|term| lower.contains(term));
        let identifier = [item.get("SYSLOG_IDENTIFIER"), item.get("_COMM")]
            .into_iter()
            .map(value_text)
            .find(|s| !s.is_empty())
            .unwrap_or_else(|| unit.to_string());
        entries.push(
            json!({"timestamp": timestamp, "level": if auth { "AUTH" } else { level },
            "message": message, "identifier": identifier}),
        );
    }
    let raw = entries
        .iter()
        .map(|entry| {
            format!(
                "{} {:<5} {}",
                timestamp_text(entry["timestamp"].as_f64().unwrap_or(0.0)),
                entry["level"].as_str().unwrap_or(""),
                entry["message"].as_str().unwrap_or("")
            )
        })
        .collect::<Vec<_>>()
        .join("\n");
    let known = issues(service, window, &raw);
    let known_strings: Vec<String> = known
        .iter()
        .map(|item| {
            format!(
                "{} — {} {}",
                item["title"].as_str().unwrap_or(""),
                item["detail"].as_str().unwrap_or(""),
                item["recovery"].as_str().unwrap_or("")
            )
        })
        .collect();
    let display = if raw.is_empty() {
        "No matching log entries.".to_string()
    } else {
        raw
    };
    json!({"ok": true, "service": service, "severity": severity, "window": window, "search": search,
        "entries": entries, "raw": display, "text": display, "known_issues": known_strings,
        "known_issue_objects": known, "bounded": true, "entry_count": entries.len()})
}
