//! Assemble one coherent live model from already-collected evidence in one process.
//! Collection, state locking, and atomic persistence remain with the controller.
use serde_json::{json, Value};
use std::io::{self, Read};

fn yes(value: &Value) -> bool {
    crate::py_truthy(Some(value))
}

pub fn derive(input: &Value) -> Option<Value> {
    let raw_services = &input["raw_services"];
    let tailscale = &input["tailscale"];
    let exposure = &input["exposure"];
    let graphical = &input["graphical"];
    let slow = &input["slow"];
    let wayvnc_security = &input["wayvnc_security"];
    let audit = crate::audit::derive(&json!({
        "services": raw_services, "tailscale": tailscale, "exposure": exposure,
        "slow": slow, "wayvnc_security": wayvnc_security,
        "hardening": input["hardening"], "integrity": input["integrity"],
        "user": input["user"], "paths": input["paths"],
    }));
    let services = crate::domain::compute(json!({
        "services": raw_services, "tailscale": tailscale, "exposure": exposure,
        "graphical": graphical, "ssh": slow["ssh"],
        "wayvnc_security": wayvnc_security,
    }))?;
    let profile = if yes(&services["wayvnc"]["ready"]) {
        "Remote desktop"
    } else if yes(&services["lan_share"]["reachable"]) {
        "File sharing"
    } else if yes(&services["sshd"]["running"]) && yes(&tailscale["connected"]) {
        "Secure idle"
    } else {
        "Custom"
    };
    let checked_at = &input["checked_at"];
    let revision = &input["backend_revision"];
    let mut state = json!({
        "schema_version": input["schema_version"], "ui_contract": input["ui_contract"],
        "backend_revision": revision, "generation": input["generation"],
        "generated_at": checked_at, "fast_checked_at": checked_at,
        "slow_checked_at": slow["checked_at"], "health": audit["health"],
        "profile": profile, "host": input["host"], "services": services,
        "tailscale": tailscale, "listeners": input["listeners"],
        "exposure": exposure, "security_checks": audit["checks"],
        "ssh": slow["ssh"], "ssh_auth": slow.get("ssh_auth").cloned().unwrap_or(json!({})),
        "ssh_host_fingerprint": slow["ssh_host_fingerprint"],
        "interfaces": slow["interfaces"], "wake": slow["wake"],
        "linger": slow["linger"], "lid": slow["lid"],
        "graphical": graphical, "wayvnc_security": wayvnc_security,
        "hardening": input["hardening"], "deployment_integrity": input["integrity"],
    });
    let guide = crate::phone_guide::derive(&json!({
        "state": state, "slow": slow, "support": input["support"],
        "qrencode_available": input["qrencode_available"],
        "user": input["user"], "home": input["home"],
    }));
    let activity = crate::activity::derive(
        &state,
        &input["activity_existing"],
        input["activity_now"].as_f64().unwrap_or(0.0),
    );
    state["phone_guide"] = guide;
    state["activity"] = activity["events"].clone();
    state["cache"] = json!({"source": "live", "age_seconds": 0.0,
        "current_backend_revision": revision, "cached_backend_revision": revision});
    Some(json!({"state": state, "activity": activity}))
}

pub fn run() -> Value {
    let mut bytes = Vec::new();
    if io::stdin().take(4_194_305).read_to_end(&mut bytes).is_err() || bytes.len() > 4_194_304 {
        return json!({"error": true, "message": "Live evidence is too large"});
    }
    serde_json::from_slice::<Value>(&bytes)
        .ok()
        .and_then(|input| derive(&input))
        .unwrap_or_else(|| json!({"error": true, "message": "Invalid live evidence"}))
}
