//! Non-disruptive security simulations and live validation.
use serde_json::{json, Value};

use crate::{domain, lan_share_security, native_snapshot, pair_support, pairing_readiness};

fn row(name: &str, passed: bool, detail: Value) -> Value {
    json!({"name": name, "passed": passed, "detail": detail})
}

pub fn selftest() -> Value {
    let raw = json!({"sshd": {"running": true, "pid": 1},
        "tailscaled": {"running": true, "pid": 2},
        "lan_share": {"running": true, "pid": 3},
        "wayvnc": {"running": true, "pid": 4}});
    let tailnet = json!({"connected": true,
        "serve": {"configured": true, "tailnet_only": true, "verification": "tailnet-only",
            "upstream_reachable": true},
        "funnel": {"is_public": false, "verification": "tailnet-only"}});
    let exposure = json!({"listeners": [
        {"port": 22, "endpoint": "0.0.0.0:22", "bind_scope": "all-interfaces", "pid": 1, "process": "sshd"},
        {"port": 8000, "endpoint": "127.0.0.1:8000", "bind_scope": "loopback", "pid": 3, "process": "python3"},
        {"port": 5900, "endpoint": "100.64.0.1:5900", "bind_scope": "tailnet", "pid": 4, "process": "wayvnc"}]});
    let graphical = json!({"hyprland_available": true, "wayland_display": "wayland-1"});
    let ssh = json!({"effective_verified": true, "secure": true});
    let auth = json!({"ok": true, "auth_mode": "TLS + password"});
    let compute =
        |raw: Value, tailnet: Value, exposure: Value, graphical: Value, ssh: Value, auth: Value| {
            domain::compute(
                json!({"services": raw, "tailscale": tailnet, "exposure": exposure,
            "graphical": graphical, "ssh": ssh, "wayvnc_security": auth}),
            )
            .unwrap_or(Value::Null)
        };
    let good = compute(
        raw.clone(),
        tailnet.clone(),
        exposure.clone(),
        graphical.clone(),
        ssh.clone(),
        auth.clone(),
    );
    let no_auth = compute(
        raw.clone(),
        tailnet.clone(),
        exposure.clone(),
        graphical.clone(),
        ssh.clone(),
        json!({"ok": false}),
    );
    let no_ssh = compute(
        raw.clone(),
        tailnet.clone(),
        exposure.clone(),
        graphical.clone(),
        json!({"effective_verified": false, "secure": false}),
        auth.clone(),
    );
    let no_tailnet = compute(
        raw.clone(),
        json!({"connected": false, "serve": tailnet["serve"],
        "funnel": tailnet["funnel"]}),
        exposure.clone(),
        graphical.clone(),
        ssh.clone(),
        auth.clone(),
    );
    let no_wayland = compute(
        raw.clone(),
        tailnet.clone(),
        exposure.clone(),
        json!({"hyprland_available": false,
        "wayland_display": ""}),
        ssh.clone(),
        auth.clone(),
    );
    let mut no_share_listener = exposure.clone();
    no_share_listener["listeners"]
        .as_array_mut()
        .unwrap()
        .retain(|item| item["port"] != 8000);
    let no_share = compute(
        raw,
        tailnet.clone(),
        no_share_listener,
        graphical,
        ssh,
        auth,
    );
    let readiness = pairing_readiness::derive(&json!({"state": {"services": good,
        "tailscale": tailnet}, "support": {"installed": false, "available": false},
        "qrencode_available": false}));
    let checks = vec![
        row(
            "LAN Share ready with loopback listener",
            good["lan_share"]["ready"] == true,
            good["lan_share"]["readiness_reason"].clone(),
        ),
        row(
            "WayVNC ready with private listener and auth",
            good["wayvnc"]["ready"] == true,
            good["wayvnc"]["readiness_reason"].clone(),
        ),
        row(
            "WayVNC without auth fails closed",
            no_auth["wayvnc"]["ready"] != true && no_auth["wayvnc"]["transport_ready"] == true,
            no_auth["wayvnc"]["readiness_reason"].clone(),
        ),
        row(
            "Unverified SSH policy is not ready",
            no_ssh["sshd"]["ready"] != true,
            no_ssh["sshd"]["readiness_reason"].clone(),
        ),
        row(
            "Disconnected tailnet is not ready",
            no_tailnet["tailscaled"]["ready"] != true,
            no_tailnet["tailscaled"]["readiness_reason"].clone(),
        ),
        row(
            "WayVNC requires Wayland",
            no_wayland["wayvnc"]["ready"] != true,
            no_wayland["wayvnc"]["readiness_reason"].clone(),
        ),
        row(
            "LAN Share requires loopback listener",
            no_share["lan_share"]["ready"] != true,
            no_share["lan_share"]["readiness_reason"].clone(),
        ),
        row(
            "Pairing requires installed dependencies",
            readiness["available"] != true,
            readiness["reason"].clone(),
        ),
    ];
    json!({"ok": checks.iter().all(|item| item["passed"] == true),
        "scenario_count": checks.len(), "checks": checks})
}

pub fn validate() -> Value {
    let state = native_snapshot::run(true);
    if state["error"] == true {
        return state;
    }
    let mut checks = Vec::new();
    let services = &state["services"];
    let ssh = &state["ssh"];
    let tailnet = &state["tailscale"];
    checks.push(row(
        "SSH active",
        services["sshd"]["running"] == true,
        services["sshd"]["active_state"].clone(),
    ));
    checks.push(row(
        "SSH boot enabled",
        services["sshd"]["boot_enabled"] == true,
        services["sshd"]["enabled_state"].clone(),
    ));
    checks.push(row(
        "SSH configured key-only",
        ssh["configured"]["pubkey_authentication"] == "yes"
            && ssh["configured"]["password_authentication"] == "no",
        ssh["configured"].clone(),
    ));
    checks.push(row(
        "SSH effective policy verified",
        ssh["effective_verified"] == true,
        ssh["source"].clone(),
    ));
    checks.push(row(
        "Tailscale connected",
        tailnet["connected"] == true,
        tailnet["backend_state"].clone(),
    ));
    let private = tailnet["serve"]["tailnet_only"] == true
        && tailnet["serve"]["verification"] == "tailnet-only"
        && matches!(
            tailnet["funnel"]["verification"].as_str(),
            Some("off" | "tailnet-only")
        )
        && tailnet["funnel"]["is_public"] != true;
    checks.push(row("Private Serve/Funnel exposure positively verified", private,
        json!({"serve": tailnet["serve"]["verification"], "funnel": tailnet["funnel"]["verification"]})));
    checks.push(row(
        "Wi-Fi WoWLAN detection",
        state["wake"]["wifi"]["capability"] != "unknown",
        state["wake"]["wifi"].clone(),
    ));
    checks.push(row(
        "Linger detected",
        state["linger"]["value"] != "unknown",
        state["linger"]["value"].clone(),
    ));
    checks.push(row(
        "No known service bind violations",
        state["exposure"]["unexpected_count"] == 0,
        state["exposure"]["groups"]["unexpected"].clone(),
    ));
    let binary = native_snapshot::lan_share_binary();
    let share_security = lan_share_security::run(&binary);
    checks.push(row(
        "LAN Share security contract",
        share_security["ok"] == true,
        share_security,
    ));
    let support = pair_support::run(&binary);
    checks.push(row("LAN Share pairing command detected", support["available"] == true,
        json!({"status": support["status"], "binary": support["binary"], "source": support["source"]})));
    if services["lan_share"]["running"] == true {
        checks.push(row(
            "LAN Share readiness",
            services["lan_share"]["ready"] == true,
            services["lan_share"]["readiness_reason"].clone(),
        ));
    }
    checks.push(row(
        "WayVNC security contract",
        state["wayvnc_security"]["ok"] == true,
        state["wayvnc_security"].clone(),
    ));
    checks.push(row(
        "User service hardening contract",
        state["hardening"]["ok"] == true,
        state["hardening"].clone(),
    ));
    checks.push(row(
        "Deployment integrity manifest",
        state["deployment_integrity"]["ok"] == true,
        state["deployment_integrity"].clone(),
    ));
    if services["wayvnc"]["running"] == true {
        checks.push(row(
            "WayVNC readiness",
            services["wayvnc"]["ready"] == true,
            services["wayvnc"]["readiness_reason"].clone(),
        ));
    }
    let tests = selftest();
    checks.push(row(
        "Non-disruptive degraded-state simulation",
        tests["ok"] == true,
        tests,
    ));
    json!({"ok": checks.iter().all(|item| item["passed"] == true), "checks": checks,
        "state_summary": {"health": state["health"], "serve": tailnet["serve"],
            "funnel": tailnet["funnel"], "wake": state["wake"], "lid": state["lid"],
            "generation": state["generation"]}})
}
