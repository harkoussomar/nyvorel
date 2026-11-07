//! Verify package-owned systemd user-service sandbox directives.
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};
use std::fs;

const REQUIRED: [(&str, &str); 16] = [
    ("NoNewPrivileges", "yes"),
    ("PrivateTmp", "yes"),
    ("ProtectSystem", "full"),
    ("ProtectKernelTunables", "yes"),
    ("ProtectKernelModules", "yes"),
    ("ProtectKernelLogs", "yes"),
    ("ProtectControlGroups", "yes"),
    ("ProtectClock", "yes"),
    ("ProtectHostname", "yes"),
    ("RestrictSUIDSGID", "yes"),
    ("LockPersonality", "yes"),
    ("RestrictRealtime", "yes"),
    ("RestrictNamespaces", "yes"),
    ("SystemCallArchitectures", "native"),
    ("UMask", "0077"),
    ("RestrictAddressFamilies", "AF_UNIX AF_INET AF_INET6"),
];

fn parse(path: &str) -> HashMap<String, String> {
    let mut values = HashMap::new();
    let Ok(content) = fs::read_to_string(path) else {
        return values;
    };
    for raw in content.lines() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with(['#', ';', '[']) {
            continue;
        }
        if let Some((key, value)) = line.split_once('=') {
            values.insert(key.trim().to_string(), value.trim().to_string());
        }
    }
    values
}

fn service(path: &str) -> Value {
    let values = parse(path);
    let mut missing = Vec::new();
    let mut directives = serde_json::Map::new();
    for (key, expected) in REQUIRED {
        let actual = values.get(key).map(String::as_str).unwrap_or("");
        directives.insert(key.into(), json!(actual));
        let ok = if key == "RestrictAddressFamilies" {
            let actual_words: HashSet<_> = actual.split_whitespace().collect();
            let expected_words: HashSet<_> = expected.split_whitespace().collect();
            actual_words == expected_words
        } else {
            actual.trim().eq_ignore_ascii_case(expected)
        };
        if !ok {
            missing.push(format!("{key}={expected}"));
        }
    }
    json!({"ok": missing.is_empty(), "path": path, "missing": missing, "directives": directives})
}

pub fn run(lan: &str, wayvnc: &str) -> Value {
    let share = service(lan);
    let vnc = service(wayvnc);
    json!({"ok": share["ok"] == true && vnc["ok"] == true,
        "security_revision": "3.0-phase3-final",
        "services": {"lan-share": share, "wayvnc-remote": vnc}})
}
