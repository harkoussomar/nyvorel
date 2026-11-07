//! Effective SSH policy with provenance-bound proof caching.
use serde_json::{json, Map, Value};
use std::fs;
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Duration;

use crate::{atomic_json, find_exe, home, now, process, read_json, sshd_effective};

const DROPIN: &str = "/etc/ssh/sshd_config.d/99-remote.conf";

fn file_signature(path: &Path) -> Value {
    match fs::metadata(path) {
        Ok(meta) => {
            json!({"mtime_ns": meta.mtime() * 1_000_000_000 + meta.mtime_nsec(), "size": meta.len()})
        }
        Err(_) => Value::Null,
    }
}

fn signatures(paths: &[&str]) -> Value {
    let mut map = Map::new();
    for path in paths {
        map.insert((*path).into(), file_signature(Path::new(path)));
    }
    Value::Object(map)
}

fn runtime_signature() -> Value {
    let service = if find_exe("systemctl").is_some() {
        let result = process::run(Command::new("systemctl").args([
            "show", "sshd.service", "--no-pager",
            "--property=MainPID,ActiveEnterTimestampMonotonic,FragmentPath,LoadState,ActiveState",
        ]), Duration::from_secs(4));
        match result {
            Ok(Some(output)) if output.status.success() => {
                let mut values = Map::new();
                for line in output.stdout.lines() {
                    if let Some((key, value)) = line.split_once('=') {
                        values.insert(key.into(), json!(value));
                    }
                }
                if values.is_empty() {
                    json!({"available": false})
                } else {
                    Value::Object(values)
                }
            }
            _ => json!({"available": false}),
        }
    } else {
        json!({"available": false})
    };
    json!({"config": signatures(&["/etc/ssh/sshd_config", DROPIN]),
        "binary": signatures(&["/usr/bin/sshd"]), "service": service})
}

fn parse_config(path: &Path) -> Map<String, Value> {
    let mut values = Map::new();
    if let Ok(content) = fs::read_to_string(path) {
        for line in content.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') || line.starts_with('[') {
                continue;
            }
            let pair = line.split_once('=').or_else(|| {
                line.find(char::is_whitespace)
                    .map(|i| (&line[..i], &line[i..]))
            });
            if let Some((key, value)) = pair {
                values.insert(key.trim().to_lowercase(), json!(value.trim()));
            }
        }
    }
    values
}

fn view(values: &Value) -> Value {
    let get = |key: &str, default: &str| {
        values
            .get(key)
            .and_then(Value::as_str)
            .unwrap_or(default)
            .to_string()
    };
    json!({"permit_root_login": get("permitrootlogin", "unknown"),
        "pubkey_authentication": get("pubkeyauthentication", "unknown"),
        "password_authentication": get("passwordauthentication", "unknown"),
        "kbd_interactive_authentication": get("kbdinteractiveauthentication", "unknown"),
        "allow_users": get("allowusers", "")})
}

fn cache_path() -> PathBuf {
    home().join(".cache/nyvorel/arch-remote/ssh-effective.json")
}

fn valid_cache() -> Option<Value> {
    let payload = read_json(&cache_path())?;
    if payload["signature"] != runtime_signature() {
        return None;
    }
    let checked = payload["checked_at"].as_f64().unwrap_or(0.0);
    if now() - checked > 86400.0 || checked <= 0.0 || !payload["values"].is_object() {
        return None;
    }
    Some(payload)
}

fn save_cache(values: &Value, source: &str) -> bool {
    let path = cache_path();
    atomic_json(
        &path,
        &json!({"checked_at": now(), "signature": runtime_signature(),
        "values": values, "source": source}),
    )
    .is_ok()
}

pub fn prove(privileged: bool) -> Value {
    let binary = if Path::new("/usr/bin/sshd").is_file() {
        "/usr/bin/sshd".to_string()
    } else {
        find_exe("sshd")
            .map(|path| path.to_string_lossy().into_owned())
            .unwrap_or_default()
    };
    let pkexec = if privileged {
        find_exe("pkexec")
            .map(|path| path.to_string_lossy().into_owned())
            .unwrap_or_default()
    } else {
        String::new()
    };
    let user = std::env::var("USER")
        .ok()
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| {
            home()
                .file_name()
                .map(|s| s.to_string_lossy().into_owned())
                .unwrap_or_default()
        });
    sshd_effective::run(&binary, &pkexec, &user, privileged)
}

pub fn verify() -> Value {
    let mut attempt = prove(false);
    if attempt["ok"] != true {
        attempt = prove(true);
    }
    if attempt["ok"] != true {
        let message = attempt["error"].as_str().unwrap_or("SSH proof failed");
        return json!({"error": true, "ok": false,
            "message": format!("Could not verify effective SSH configuration: {message}")});
    }
    let source = attempt["source"].as_str().unwrap_or("");
    if !save_cache(&attempt["values"], source) {
        return json!({"error": true, "ok": false, "message": "Could not persist SSH verification."});
    }
    json!({"ok": true, "message": "Effective SSH configuration verified with sshd -T", "source": source})
}

pub fn run() -> Value {
    let configured = Value::Object(parse_config(Path::new(DROPIN)));
    let attempt = prove(false);
    let mut effective = json!({});
    let mut verified = false;
    let source: String;
    let mut checked = 0.0;
    let error = attempt["error"].as_str().unwrap_or("").to_string();
    if attempt["ok"] == true {
        effective = attempt["values"].clone();
        verified = true;
        source = attempt["source"].as_str().unwrap_or("").to_string();
        checked = now();
        let _ = save_cache(&effective, &source);
    } else if let Some(cached) = valid_cache() {
        effective = cached["values"].clone();
        verified = true;
        source = format!(
            "{} (cached; SSH config/runtime provenance unchanged)",
            cached["source"].as_str().unwrap_or("cached sshd -T")
        );
        checked = cached["checked_at"].as_f64().unwrap_or(0.0);
    } else {
        source = "hardened SSH drop-in (configured state only)".into();
    }
    let configured_view = view(&configured);
    let effective_view = view(&effective);
    let selected = if verified {
        &effective_view
    } else {
        &configured_view
    };
    let authorized = home().join(".ssh/authorized_keys");
    let mode = fs::metadata(&authorized)
        .map(|meta| format!("0o{:o}", meta.permissions().mode() & 0o7777))
        .unwrap_or_default();
    let text = |key: &str| selected[key].as_str().unwrap_or("").to_string();
    let pubkey = text("pubkey_authentication");
    let password = text("password_authentication");
    let root = text("permit_root_login");
    let keyboard = text("kbd_interactive_authentication");
    let key_only = pubkey.eq_ignore_ascii_case("yes") && password.eq_ignore_ascii_case("no");
    let root_disabled = root.eq_ignore_ascii_case("no");
    let secure = verified && key_only && root_disabled && keyboard.eq_ignore_ascii_case("no");
    json!({"source": source, "effective_verified": verified, "effective_error": error,
        "effective_checked_at": checked, "verification_available": find_exe("pkexec").is_some() || attempt["ok"] == true,
        "configured": configured_view, "effective": effective_view, "dropin_path": DROPIN,
        "dropin_exists": Path::new(DROPIN).is_file(), "permit_root_login": root,
        "pubkey_authentication": pubkey, "password_authentication": password,
        "kbd_interactive_authentication": keyboard, "allow_users": text("allow_users"),
        "authorized_keys_exists": authorized.is_file(), "authorized_keys_mode": mode,
        "key_only": key_only, "root_disabled": root_disabled, "secure": secure})
}
