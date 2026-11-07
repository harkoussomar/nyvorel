//! Read-only WayVNC authentication and launcher posture. Never return the password.
use crate::{integrity, process};
use regex::Regex;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::ffi::CString;
use std::fs;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::path::Path;
use std::process::Command;
use std::time::Duration;

fn values(path: &Path) -> HashMap<String, String> {
    let mut values = HashMap::new();
    let Ok(contents) = fs::read_to_string(path) else {
        return values;
    };
    for raw in contents.lines() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some((key, value)) = line.split_once('=') {
            values.insert(key.trim().to_lowercase(), value.trim().to_string());
        }
    }
    values
}

fn mode(path: &Path) -> u32 {
    fs::metadata(path)
        .map(|metadata| metadata.permissions().mode() & 0o7777)
        .unwrap_or(0)
}

fn owned(path: &Path) -> bool {
    fs::metadata(path)
        .map(|metadata| metadata.uid() == unsafe { libc::getuid() })
        .unwrap_or(false)
}

fn mode_label(value: u32) -> String {
    if value == 0 {
        "missing".into()
    } else {
        format!("0o{value:o}")
    }
}

fn executable(path: &Path) -> bool {
    CString::new(path.as_os_str().as_bytes())
        .ok()
        .is_some_and(|path| unsafe { libc::access(path.as_ptr(), libc::X_OK) == 0 })
}

pub fn run(config: &str, key: &str, cert: &str, launcher: &str, dropin: &str) -> Value {
    let config_path = Path::new(config);
    let key_path = Path::new(key);
    let cert_path = Path::new(cert);
    let launcher_path = Path::new(launcher);
    let dropin_path = Path::new(dropin);
    let cfg = values(config_path);
    let launcher_text = fs::read_to_string(launcher_path).unwrap_or_default();
    let dropin_text = fs::read_to_string(dropin_path).unwrap_or_default();
    let config_mode = mode(config_path);
    let key_mode = mode(key_path);
    let cert_mode = mode(cert_path);
    let username = cfg.get("username").map(String::as_str).unwrap_or("");
    let password = cfg.get("password").map(String::as_str).unwrap_or("");
    let enable_auth = cfg
        .get("enable_auth")
        .is_some_and(|value| value.eq_ignore_ascii_case("true"));
    let broken_crypto = cfg
        .get("allow_broken_crypto")
        .is_some_and(|value| value.eq_ignore_ascii_case("true"));
    let relaxed = cfg
        .get("relax_encryption")
        .is_some_and(|value| value.eq_ignore_ascii_case("true"));
    let tls_files_ok = key_path.is_file()
        && cert_path.is_file()
        && cfg
            .get("private_key_file")
            .is_some_and(|value| value == key)
        && cfg
            .get("certificate_file")
            .is_some_and(|value| value == cert)
        && key_mode == 0o600
        && owned(key_path)
        && owned(cert_path);
    let config_ok = config_path.is_file()
        && config_mode == 0o600
        && owned(config_path)
        && enable_auth
        && !username.is_empty()
        && password.chars().count() >= 20
        && tls_files_ok
        && !broken_crypto
        && !relaxed;
    let hardcoded_tailnet =
        Regex::new(r"\b100\.(?:\d{1,3}\.){2}\d{1,3}:5900\b").expect("static regular expression");
    let dynamic_launcher = launcher_path.is_file()
        && executable(launcher_path)
        && launcher_text.contains("tailscale ip -4")
        && launcher_text.contains("arch-remote.conf")
        && launcher_text.contains("--config")
        && !hardcoded_tailnet.is_match(&launcher_text);
    let secure_dropin = dropin_path.is_file()
        && dropin_text.contains("ExecStart=%h/.local/bin/wayvnc-remote")
        && !dropin_text.contains("/usr/bin/wayvnc");
    let effective_exec = process::run(
        Command::new("systemctl").args([
            "--user",
            "show",
            "wayvnc-remote",
            "--property=ExecStart",
            "--value",
        ]),
        Duration::from_secs(4),
    )
    .ok()
    .flatten()
    .filter(|output| output.status.success())
    .map(|output| output.stdout.trim().to_string())
    .unwrap_or_default();
    let effective_launcher =
        effective_exec.contains("wayvnc-remote") && !effective_exec.contains("100.");
    let ok = config_ok && dynamic_launcher && secure_dropin && effective_launcher;
    let mut reasons = Vec::new();
    if !config_ok {
        reasons.push(
            "TLS/password authentication configuration is incomplete or has unsafe permissions",
        );
    }
    if !dynamic_launcher {
        reasons.push("WayVNC launcher does not dynamically resolve the Tailscale IPv4 address");
    }
    if !secure_dropin {
        reasons.push("security drop-in does not force the canonical dynamic launcher");
    }
    if !effective_launcher {
        reasons.push("effective systemd ExecStart is not the canonical launcher");
    }
    let certificate_sha256 = if cert_path.is_file() {
        integrity::sha256_file(cert_path).unwrap_or_default()
    } else {
        String::new()
    };
    json!({
        "ok": ok, "security_revision": "2.2-phase1b2", "auth_required": true,
        "auth_mode": "VeNCrypt/TLS + dedicated password", "username": username,
        "password_present": !password.is_empty(), "password_length_ok": password.chars().count() >= 20,
        "config_path": config, "config_mode": mode_label(config_mode),
        "private_key_path": key, "private_key_mode": mode_label(key_mode),
        "certificate_path": cert, "certificate_mode": mode_label(cert_mode),
        "certificate_sha256": certificate_sha256,
        "dynamic_tailnet_bind": dynamic_launcher, "secure_dropin": secure_dropin,
        "effective_launcher": effective_launcher,
        "effective_exec": effective_exec.chars().take(800).collect::<String>(),
        "legacy_crypto_allowed": broken_crypto, "encryption_relaxed": relaxed,
        "tailnet_acl_verification": "external-unverified",
        "tailnet_acl_note": "Independent WayVNC authentication is enforced; Tailscale ACL policy remains a separate control-plane assurance.",
        "reason": if ok {"WayVNC TLS/password authentication and dynamic Tailscale binding verified.".to_string()}
                  else {reasons.join("; ")}
    })
}
