//! Direct Rust live collection and persistence; no Python process is launched.
use serde_json::{json, Value};
use std::fs::{self, Permissions};
use std::io::{Read, Write};
use std::net::{IpAddr, SocketAddr, TcpStream};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::time::Duration;
use url::Url;

use crate::{
    atomic_json, exposure, find_exe, graphical, hardening, home, host, integrity, interfaces,
    listeners, live_derive, now, pair_support, power, read_json, serve_funnel, services,
    ssh_evidence, ssh_policy, tailscale, wayvnc_security, Flock, REVISION, UI_CONTRACT,
};

fn state_dir() -> PathBuf {
    home().join(".local/state/nyvorel/arch-remote")
}
fn cache_dir() -> PathBuf {
    home().join(".cache/nyvorel/arch-remote")
}

fn private_dir(path: &Path) -> bool {
    fs::create_dir_all(path).is_ok()
        && fs::set_permissions(path, Permissions::from_mode(0o700)).is_ok()
}

fn error(message: &str) -> Value {
    json!({"error": true, "message": message})
}

fn user() -> String {
    std::env::var("USER")
        .ok()
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| {
            home()
                .file_name()
                .map(|part| part.to_string_lossy().into_owned())
                .unwrap_or_default()
        })
}

pub fn lan_share_binary() -> String {
    for path in [
        home().join(".local/bin/lan-share"),
        PathBuf::from("/usr/local/bin/lan-share"),
    ] {
        if path.is_file()
            && fs::metadata(&path).is_ok_and(|meta| meta.permissions().mode() & 0o111 != 0)
        {
            return path.to_string_lossy().into_owned();
        }
    }
    find_exe("lan-share")
        .map(|path| path.to_string_lossy().into_owned())
        .unwrap_or_default()
}

fn probe_local(url: &str) -> Value {
    let Ok(parsed) = Url::parse(url) else {
        return json!({"tested": false, "reachable": false, "status_code": 0});
    };
    if !matches!(parsed.scheme(), "http" | "https") {
        return json!({"tested": false, "reachable": false, "status_code": 0});
    }
    let Some(host) = parsed.host_str() else {
        return json!({"tested": false, "reachable": false, "status_code": 0});
    };
    if !matches!(host, "127.0.0.1" | "localhost" | "[::1]" | "::1") {
        return json!({"tested": false, "reachable": false, "status_code": 0});
    }
    let ip = if host == "::1" || host == "[::1]" {
        IpAddr::V6(std::net::Ipv6Addr::LOCALHOST)
    } else {
        IpAddr::V4(std::net::Ipv4Addr::LOCALHOST)
    };
    let port = parsed.port_or_known_default().unwrap_or(80);
    if parsed.scheme() == "https" {
        // No TLS handshake is attempted without an HTTPS client. Preserve the
        // fail-closed readiness state instead of treating a TCP connect as HTTP health.
        return json!({"tested": false, "reachable": false, "status_code": 0});
    }
    let address = SocketAddr::new(ip, port);
    let Ok(mut stream) = TcpStream::connect_timeout(&address, Duration::from_millis(1500)) else {
        return json!({"tested": true, "reachable": false, "status_code": 0});
    };
    let _ = stream.set_read_timeout(Some(Duration::from_millis(1500)));
    let _ = stream.set_write_timeout(Some(Duration::from_millis(1500)));
    let path = if parsed.path().is_empty() {
        "/"
    } else {
        parsed.path()
    };
    let query = parsed
        .query()
        .map(|value| format!("?{value}"))
        .unwrap_or_default();
    let request =
        format!("HEAD {path}{query} HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n\r\n");
    if stream.write_all(request.as_bytes()).is_err() {
        return json!({"tested": true, "reachable": false, "status_code": 0});
    }
    let mut buffer = [0_u8; 128];
    let Ok(count) = stream.read(&mut buffer) else {
        return json!({"tested": true, "reachable": false, "status_code": 0});
    };
    let line = String::from_utf8_lossy(&buffer[..count]);
    let status = line
        .split_whitespace()
        .nth(1)
        .and_then(|part| part.parse::<u16>().ok())
        .unwrap_or(0);
    json!({"tested": true, "reachable": status > 0, "status_code": status})
}

fn current_tailnet() -> Value {
    let mut result = tailscale::run();
    let binary = find_exe("tailscale")
        .map(|path| path.to_string_lossy().into_owned())
        .unwrap_or_default();
    let mut serve = serve_funnel::run(&binary);
    let upstream = serve["serve"]["upstream"].as_str().unwrap_or("");
    if !upstream.is_empty() {
        let probe = probe_local(upstream);
        serve["serve"]["upstream_tested"] = probe["tested"].clone();
        serve["serve"]["upstream_reachable"] = probe["reachable"].clone();
        serve["serve"]["upstream_status"] = probe["status_code"].clone();
        if serve["serve"]["configured"] == true
            && serve["serve"]["verification"] == "tailnet-only"
            && probe["tested"] == true
            && probe["reachable"] != true
        {
            serve["serve"]["health"] = json!("degraded");
        }
    }
    result["serve"] = serve["serve"].clone();
    result["funnel"] = serve["funnel"].clone();
    result
}

fn slow(force: bool) -> Value {
    let path = cache_dir().join("slow-state.json");
    if private_dir(&cache_dir()) && !force {
        if let Some(mut cached) = read_json(&path) {
            let age = now() - cached["checked_at"].as_f64().unwrap_or(0.0);
            if cached.is_object() && (0.0..90.0).contains(&age) {
                cached["ssh"] = ssh_policy::run();
                return cached;
            }
        }
    }
    let interface_state = interfaces::run();
    let items = interface_state.as_array().cloned().unwrap_or_default();
    let power_state = power::collect(&items);
    let ssh_evidence = ssh_evidence::run("/etc/ssh/ssh_host_ed25519_key.pub");
    let value = json!({"checked_at": now(), "ssh": ssh_policy::run(),
        "ssh_host_fingerprint": ssh_evidence["fingerprint"], "ssh_auth": ssh_evidence["auth"],
        "interfaces": interface_state, "wake": power_state["wake"],
        "linger": power_state["linger"], "lid": power_state["lid"]});
    let _ = atomic_json(&path, &value);
    value
}

fn next_generation() -> Option<u64> {
    let directory = state_dir();
    if !private_dir(&directory) {
        return None;
    }
    let _lock = Flock::acquire(&directory.join(".state.lock")).ok()?;
    let path = directory.join("generation.json");
    let previous = read_json(&path)
        .and_then(|value| value["generation"].as_u64())
        .unwrap_or(0);
    let next = previous.saturating_add(1);
    atomic_json(&path, &json!({"generation": next, "updated_at": now()})).ok()?;
    Some(next)
}

pub fn collect(force: bool) -> Value {
    let checked = now();
    let Some(generation) = next_generation() else {
        return error("Could not lock Arch Remote state generation.");
    };
    let raw_services = services::run();
    let tailnet = current_tailnet();
    let listener_state = listeners::run(
        tailnet["ipv4"].as_str().unwrap_or(""),
        tailnet["ipv6"].as_str().unwrap_or(""),
    );
    let Some(exposure_state) =
        exposure::compute(json!({"listeners": listener_state, "tailscale": tailnet}))
    else {
        return error("Could not classify listener exposure.");
    };
    let host_state = host::run();
    let graphical_state = graphical::run();
    let slow_state = slow(force);
    let base = home().join(".config");
    let wayvnc_config = base.join("wayvnc/arch-remote.conf");
    let wayvnc_launcher = home().join(".local/bin/wayvnc-remote");
    let wayvnc_dropin =
        base.join("systemd/user/wayvnc-remote.service.d/99-arch-remote-security.conf");
    let manifest = state_dir().join("deployment.json");
    let wayvnc_security_state = wayvnc_security::run(
        &wayvnc_config.to_string_lossy(),
        &base
            .join("wayvnc/arch-remote-tls-key.pem")
            .to_string_lossy(),
        &base
            .join("wayvnc/arch-remote-tls-cert.pem")
            .to_string_lossy(),
        &wayvnc_launcher.to_string_lossy(),
        &wayvnc_dropin.to_string_lossy(),
    );
    let hardening_state = hardening::run(
        &base
            .join("systemd/user/lan-share.service.d/20-arch-remote-hardening.conf")
            .to_string_lossy(),
        &base
            .join("systemd/user/wayvnc-remote.service.d/20-arch-remote-hardening.conf")
            .to_string_lossy(),
    );
    let integrity_state = integrity::run(&manifest.to_string_lossy());
    let support = pair_support::run(&lan_share_binary());
    json!({"checked_at": checked, "generation": generation,
        "schema_version": 2, "ui_contract": UI_CONTRACT, "backend_revision": REVISION,
        "raw_services": raw_services, "tailscale": tailnet, "listeners": listener_state,
        "exposure": exposure_state, "host": host_state, "graphical": graphical_state,
        "slow": slow_state, "wayvnc_security": wayvnc_security_state,
        "hardening": hardening_state, "integrity": integrity_state, "support": support,
        "qrencode_available": find_exe("qrencode").is_some(), "user": user(),
        "home": home().to_string_lossy(),
        "paths": {"ssh_dropin": "/etc/ssh/sshd_config.d/99-remote.conf",
            "wayvnc_config": wayvnc_config.to_string_lossy(),
            "wayvnc_launcher": wayvnc_launcher.to_string_lossy(),
            "wayvnc_dropin": wayvnc_dropin.to_string_lossy(),
            "manifest": manifest.to_string_lossy()}})
}

pub fn run(full: bool) -> Value {
    let mut input = collect(full);
    if input.get("error") == Some(&Value::Bool(true)) {
        return input;
    }
    let directory = state_dir();
    let Ok(_lock) = Flock::acquire(&directory.join(".state.lock")) else {
        return error("Arch Remote state is busy.");
    };
    let activity_path = directory.join("activity.json");
    let existing = read_json(&activity_path)
        .filter(|value| value["events"].is_array())
        .unwrap_or_else(|| json!({"previous": {}, "events": []}));
    input["activity_existing"] = existing;
    input["activity_now"] = json!(now());
    let Some(derived) = live_derive::derive(&input) else {
        return error("Could not derive live state.");
    };
    let state = &derived["state"];
    let events = &derived["activity"];
    if state["schema_version"] != 2
        || state["services"]
            .as_object()
            .is_none_or(|map| map.len() != 4)
        || state["security_checks"]
            .as_array()
            .is_none_or(|items| items.len() < 15)
    {
        return error("Derived live state failed contract checks.");
    }
    if atomic_json(&activity_path, events).is_err()
        || atomic_json(&directory.join("runtime-state.json"), state).is_err()
    {
        return error("Could not persist Arch Remote state.");
    }
    state.clone()
}
