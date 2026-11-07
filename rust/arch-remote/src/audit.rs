//! Security audit and health summary from already-collected evidence.
//! No commands are run here; the caller provides one consistent evidence set.
use serde_json::{json, Value};
use std::io::{self, Read};

fn s(value: &Value) -> String {
    match value {
        Value::String(value) => value.clone(),
        Value::Null => String::new(),
        Value::Bool(value) => if *value { "True" } else { "False" }.into(),
        _ => value.to_string(),
    }
}

fn field(value: &Value, key: &str) -> String {
    s(&value[key])
}

fn truth(value: &Value) -> bool {
    super::py_truthy(Some(value))
}

fn item_words(value: &Value) -> Vec<&str> {
    value.as_str().unwrap_or("").split_whitespace().collect()
}

#[expect(
    clippy::too_many_arguments,
    reason = "preserves the reviewed audit-check contract"
)]
fn check(
    id: &str,
    category: &str,
    severity: &str,
    status: &str,
    title: &str,
    expected: &str,
    detected: &str,
    source: &str,
    explanation: &str,
    remediation: &str,
) -> Value {
    json!({"id": id, "category": category, "severity": severity, "status": status,
        "title": title, "expected": expected, "detected": detected, "current": detected,
        "source": source, "evidence_sources": if source.is_empty() {vec![]} else {vec![source]},
        "checked_at": crate::now(), "explanation": explanation, "remediation": remediation,
        "repair_available": false, "privilege": "none", "verification_scope": "local",
        "confidence": "verified"})
}

fn options(
    mut check: Value,
    privilege: &str,
    scope: &str,
    confidence: &str,
    repair: bool,
    evidence: Vec<String>,
) -> Value {
    check["privilege"] = json!(privilege);
    check["verification_scope"] = json!(scope);
    check["confidence"] = json!(confidence);
    check["repair_available"] = json!(repair);
    check["evidence_sources"] = json!(evidence);
    check
}

fn health(checks: &[Value], tailscale: &Value) -> Value {
    let critical = checks
        .iter()
        .filter(|item| item["status"] == "fail" && item["severity"] == "critical")
        .count();
    let mut warnings = checks
        .iter()
        .filter(|item| {
            (item["status"] == "warn" || item["status"] == "fail") && item["severity"] != "critical"
        })
        .count();
    let local = checks
        .iter()
        .filter(|item| {
            item["verification_scope"] == "local"
                && (item["status"] == "unknown" || item["status"] == "untested")
        })
        .count();
    let external = checks
        .iter()
        .filter(|item| {
            item["verification_scope"] == "external" && item["status"] == "external-unverified"
        })
        .count();
    if truth(&tailscale["health_messages"]) {
        warnings += 1;
    }
    let verified = checks
        .iter()
        .filter(|item| item["status"] == "pass")
        .count();
    let (status, label, summary) = if critical > 0 {
        (
            "critical",
            "Critical",
            format!(
                "{critical} critical issue{}",
                if critical == 1 { "" } else { "s" }
            ),
        )
    } else if warnings > 0 {
        (
            "degraded",
            "Degraded",
            format!(
                "{warnings} warning{} · 0 critical",
                if warnings == 1 { "" } else { "s" }
            ),
        )
    } else if local > 0 {
        (
            "operational",
            "Operational",
            format!("{verified} verified · {local} local unverified · 0 issues"),
        )
    } else if external > 0 {
        (
            "healthy-locally",
            "Healthy locally",
            "External exposure not tested".to_string(),
        )
    } else {
        (
            "healthy",
            "Healthy",
            format!("{verified} verified · 0 issues"),
        )
    };
    json!({"status": status, "label": label, "title": label, "summary": summary,
        "critical_count": critical, "warning_count": warnings, "verified_count": verified,
        "passed_count": verified, "local_unverified_count": local,
        "external_unverified_count": external, "unverified_count": local+external,
        "check_count": checks.len(), "issue_count": critical+warnings})
}

pub fn derive(input: &Value) -> Value {
    let services = &input["services"];
    let tailscale = &input["tailscale"];
    let exposure = &input["exposure"];
    let slow = &input["slow"];
    let ssh = &slow["ssh"];
    let wayvnc = &input["wayvnc_security"];
    let hardening = &input["hardening"];
    let integrity = &input["integrity"];
    let paths = &input["paths"];
    let user = field(input, "user");
    let ssh_dropin = field(paths, "ssh_dropin");
    let wayvnc_config = field(paths, "wayvnc_config");
    let wayvnc_launcher = field(paths, "wayvnc_launcher");
    let wayvnc_dropin = field(paths, "wayvnc_dropin");
    let manifest = field(paths, "manifest");
    let mut checks = Vec::new();
    checks.push(options(
        check(
            "sshd-active",
            "SSH",
            "critical",
            if truth(&services["sshd"]["running"]) {
                "pass"
            } else {
                "fail"
            },
            "SSH recovery service is running",
            "active",
            &field(&services["sshd"], "active_state"),
            "systemd",
            "SSH is the primary recovery path.",
            "Inspect sshd before changing authentication.",
        ),
        "root",
        "local",
        "verified",
        false,
        vec!["systemd".into()],
    ));
    checks.push(options(
        check(
            "tailscale-active",
            "Tailscale",
            "critical",
            if truth(&tailscale["connected"]) {
                "pass"
            } else {
                "fail"
            },
            "Tailscale is connected",
            "Running",
            &field(tailscale, "backend_state"),
            "tailscale status --json",
            "The tailnet provides private remote reachability.",
            "Inspect tailscaled and authentication state.",
        ),
        "root",
        "local",
        "verified",
        false,
        vec!["systemd".into(), "tailscale status --json".into()],
    ));

    let configured = &ssh["configured"];
    let configured_ok = field(configured, "permit_root_login").to_lowercase() == "no"
        && field(configured, "password_authentication").to_lowercase() == "no"
        && field(configured, "pubkey_authentication").to_lowercase() == "yes"
        && field(configured, "kbd_interactive_authentication").to_lowercase() == "no"
        && item_words(&configured["allow_users"]) == [user.as_str()];
    checks.push(options(
        check(
            "ssh-configured-policy",
            "SSH",
            "warning",
            if configured_ok { "pass" } else { "warn" },
            "SSH hardening is configured",
            "root off · password off · pubkey on · intended user only",
            if configured_ok {
                "matches configured policy"
            } else {
                "configured values differ"
            },
            &ssh_dropin,
            "This proves the configuration file intent, not the running daemon's effective state.",
            "Review the hardened SSH drop-in before making changes.",
        ),
        "none",
        "local",
        "configured",
        false,
        vec![ssh_dropin.clone()],
    ));

    if truth(&ssh["effective_verified"]) {
        let effective = &ssh["effective"];
        for (id, title, key, expected, severity) in [
            (
                "root-off",
                "Root login disabled",
                "permit_root_login",
                "no",
                "critical",
            ),
            (
                "password-off",
                "Password authentication disabled",
                "password_authentication",
                "no",
                "critical",
            ),
            (
                "pubkey-on",
                "Public-key authentication enabled",
                "pubkey_authentication",
                "yes",
                "critical",
            ),
            (
                "kbd-off",
                "Keyboard-interactive authentication disabled",
                "kbd_interactive_authentication",
                "no",
                "warning",
            ),
        ] {
            let detected = effective[key].as_str().unwrap_or("unknown");
            checks.push(options(
                check(
                    id,
                    "SSH",
                    severity,
                    if detected.to_lowercase() == expected {
                        "pass"
                    } else {
                        "fail"
                    },
                    title,
                    expected,
                    detected,
                    &field(ssh, "source"),
                    "Verified against the daemon's effective configuration.",
                    "Review the effective sshd policy before changing authentication.",
                ),
                "root",
                "local",
                "verified",
                false,
                vec!["sshd -T".into(), ssh_dropin.clone()],
            ));
        }
        let allow = &effective["allow_users"];
        checks.push(options(
            check(
                "allow-user",
                "SSH",
                "critical",
                if item_words(allow) == [user.as_str()] {
                    "pass"
                } else {
                    "fail"
                },
                "SSH is restricted to the intended account",
                &user,
                if truth(allow) {
                    allow.as_str().unwrap_or("")
                } else {
                    "not declared"
                },
                &field(ssh, "source"),
                "AllowUsers is verified from sshd -T.",
                "Review AllowUsers before editing SSH.",
            ),
            "root",
            "local",
            "verified",
            false,
            vec!["sshd -T".into()],
        ));
        checks.push(options(
            check(
                "ssh-effective-proof",
                "SSH",
                "info",
                "pass",
                "Effective SSH configuration independently verified",
                "sshd -T verified",
                &field(ssh, "source"),
                &field(ssh, "source"),
                "Configured and effective SSH state are independently distinguished.",
                "No action required.",
            ),
            "none",
            "local",
            "verified",
            false,
            vec!["sshd -T".into()],
        ));
    } else {
        let effective_error = if truth(&ssh["effective_error"]) {
            field(ssh, "effective_error")
        } else {
            "not verified".into()
        };
        checks.push(options(check("ssh-effective-proof", "SSH", "warning", "unknown",
            "Effective SSH configuration needs verification", "effective sshd -T output", &effective_error,
            &field(ssh,"source"),
            "Configured hardening looks correct, but this local claim is important enough to require effective daemon evidence.",
            "Use Verify SSH. The app performs a targeted sshd -T check and may request Polkit authorization."),
            "root", "local", "unverified", true, vec![ssh_dropin.clone()]));
    }

    let funnel = &tailscale["funnel"];
    let funnel_verification = field(funnel, "verification");
    let funnel_status = if truth(&funnel["is_public"]) {
        "fail"
    } else if ["tailnet-only", "off"].contains(&funnel_verification.as_str()) {
        "pass"
    } else {
        "unknown"
    };
    checks.push(options(
        check(
            "funnel-off",
            "Exposure",
            "critical",
            funnel_status,
            "Tailscale Funnel is not public",
            "off / tailnet-only",
            &funnel_verification,
            &field(funnel, "source"),
            "Serve is tailnet-private; Funnel is internet-public.",
            "Disable Funnel if public exposure is not intentional.",
        ),
        "none",
        "local",
        "verified",
        false,
        vec!["tailscale funnel status".into()],
    ));
    let serve = &tailscale["serve"];
    let serve_verification = if truth(&serve["verification"]) {
        field(serve, "verification")
    } else {
        "unknown".into()
    };
    let serve_status = if !truth(&serve["configured"])
        || (serve_verification == "tailnet-only" && serve["tailnet_only"] == true)
    {
        "pass"
    } else if serve_verification == "public" || truth(&serve["is_public"]) {
        "fail"
    } else {
        "unknown"
    };
    checks.push(options(check("serve-private-proof", "Exposure", "critical", serve_status,
        "Tailscale Serve privacy is positively classified", "off / tailnet-only", &serve_verification,
        serve["source"].as_str().unwrap_or("tailscale serve status"),
        "A configured route is not automatically private; the tailnet-only marker must be observed.",
        "Keep private actions blocked until Serve is explicitly verified tailnet-only."),
        "none", "local", if serve_status == "pass" {"verified"} else {"unverified"}, false,
        vec!["tailscale serve status".into()]));

    let unexpected = exposure["groups"]["unexpected"]
        .as_array()
        .cloned()
        .unwrap_or_default();
    let detected = if unexpected.is_empty() {
        "expected binds".to_string()
    } else {
        unexpected
            .iter()
            .map(|item| field(item, "endpoint"))
            .collect::<Vec<_>>()
            .join(", ")
    };
    checks.push(options(
        check(
            "application-exposure",
            "Exposure",
            "critical",
            if unexpected.is_empty() {
                "pass"
            } else {
                "fail"
            },
            "Known remote services follow their local bind policy",
            "no unexpected LAN Share / WayVNC exposure",
            &detected,
            "ss listener policy model",
            "Local listeners and application-level exposure can be verified from this machine.",
            "Stop the affected service and repair its bind policy.",
        ),
        "none",
        "local",
        "verified",
        false,
        vec!["ss".into(), "Tailscale Serve/Funnel state".into()],
    ));
    checks.push(options(check("router-nat", "External exposure", "info", "external-unverified",
        "Router/NAT exposure", "external reachability test", "outside local verification scope", "local machine only",
        "The control center does not claim that router/NAT forwarding is absent without external evidence.",
        "Use an external probe or router integration if that assurance is required."),
        "none", "external", "externally-unverified", false, vec!["local machine only".into()]));

    checks.push(options(
        check(
            "share-demand",
            "Services",
            "warning",
            if truth(&services["lan_share"]["boot_enabled"]) {
                "warn"
            } else {
                "pass"
            },
            "LAN Share remains on-demand",
            "disabled",
            &field(&services["lan_share"], "enabled_state"),
            "systemd user unit state",
            "LAN Share is intentionally not a boot service.",
            "Disable boot enablement if it was enabled unintentionally.",
        ),
        "user",
        "local",
        "verified",
        true,
        vec!["systemd --user".into()],
    ));
    checks.push(options(
        check(
            "vnc-demand",
            "Services",
            "warning",
            if truth(&services["wayvnc"]["boot_enabled"]) {
                "warn"
            } else {
                "pass"
            },
            "WayVNC remains on-demand",
            "disabled",
            &field(&services["wayvnc"], "enabled_state"),
            "systemd user unit state",
            "Remote desktop is intentionally not a boot service.",
            "Disable boot enablement if it was enabled unintentionally.",
        ),
        "user",
        "local",
        "verified",
        true,
        vec!["systemd --user".into()],
    ));
    checks.push(options(check("vnc-auth", "Remote desktop", "critical", if truth(&wayvnc["ok"]) {"pass"} else {"fail"},
        "WayVNC requires independent encrypted authentication",
        "VeNCrypt/TLS + dedicated password + dynamic Tailscale bind",
        wayvnc["reason"].as_str().unwrap_or("unverified"), &wayvnc_config,
        "Tailnet binding is transport isolation; WayVNC authentication is a separate authorization layer.",
        "Repair the Arch Remote WayVNC security profile before starting remote desktop."),
        "none", "local", "verified", false, vec![wayvnc_config.clone(),wayvnc_launcher,wayvnc_dropin]));
    checks.push(options(
        check(
            "linger",
            "Services",
            "warning",
            if truth(&slow["linger"]["enabled"]) {
                "pass"
            } else {
                "warn"
            },
            "User linger is enabled",
            "yes",
            &field(&slow["linger"], "value"),
            &field(&slow["linger"], "source"),
            "Linger keeps user services manageable outside an interactive login.",
            "Enable linger intentionally if remote user services require it.",
        ),
        "root",
        "local",
        "verified",
        false,
        vec!["loginctl".into()],
    ));

    for name in ["lan-share", "wayvnc-remote"] {
        let posture = &hardening["services"][name];
        let status = if truth(&posture["ok"]) {
            "pass"
        } else {
            "warn"
        };
        let detected = if status == "pass" {
            "verified".to_string()
        } else {
            let value = posture["missing"]
                .as_array()
                .into_iter()
                .flatten()
                .map(s)
                .collect::<Vec<_>>()
                .join("; ");
            if value.is_empty() {
                "missing".into()
            } else {
                value
            }
        };
        let path = field(posture, "path");
        checks.push(options(check(&format!("{name}-sandbox"), "Services", "warning", status,
            &format!("{name} runs with the Arch Remote sandbox profile"), "3.0-phase3-final", &detected,
            &path, "The service remains able to use its intended user files/network while unnecessary kernel and privilege surfaces are restricted.",
            "Restore the package-owned hardening drop-in before using the service."),
            "none", "local", "verified", false, vec![path]));
    }
    checks.push(options(
        check(
            "deployment-integrity",
            "Integrity",
            "warning",
            if truth(&integrity["ok"]) {
                "pass"
            } else {
                "warn"
            },
            "Arch Remote package-owned files match the installed manifest",
            "all managed hashes and modes match",
            &field(integrity, "reason"),
            &manifest,
            "This detects accidental source/config drift after the reviewed deployment.",
            "Re-run the reviewed installer or perform a new audit before accepting changed files.",
        ),
        "none",
        "local",
        "verified",
        false,
        vec![manifest],
    ));

    let summary = health(&checks, tailscale);
    json!({"checks": checks, "health": summary})
}

pub fn run() -> Value {
    let mut input = Vec::new();
    if io::stdin().take(2_097_152).read_to_end(&mut input).is_err() {
        return json!({"error": true, "message": "Could not read audit evidence"});
    }
    let Ok(input) = serde_json::from_slice::<Value>(&input) else {
        return json!({"error": true, "message": "Invalid audit evidence"});
    };
    derive(&input)
}
