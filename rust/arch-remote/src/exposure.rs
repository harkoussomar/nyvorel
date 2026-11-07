//! Classify TCP listeners and application-level exposure from explicit inputs.
//! No network commands or mutations occur here.
use serde_json::{json, Map, Value};
use std::io::{self, Read};

fn string<'a>(value: &'a Value, key: &str) -> &'a str {
    value.get(key).and_then(Value::as_str).unwrap_or("")
}

fn assign(result: &mut Map<String, Value>, fields: &[(&str, &str)]) {
    for (key, value) in fields {
        result.insert((*key).into(), json!(value));
    }
}

fn classify(entry: &Value, tailscale: &Value) -> Option<Value> {
    let Value::Object(mut result) = entry.clone() else {
        return None;
    };
    let port = entry.get("port")?.as_i64()?;
    let bind_scope = string(entry, "bind_scope");
    let process = string(entry, "process");
    result.insert(
        "service".into(),
        json!(if process.is_empty() {
            format!("TCP {port}")
        } else {
            process.to_string()
        }),
    );
    assign(
        &mut result,
        &[
            ("reachable_scope", "Unknown"),
            ("expected_policy", "No explicit policy"),
            ("policy_status", "informational"),
            ("finding", "info"),
            ("group", "other"),
        ],
    );
    if port == 22 {
        assign(
            &mut result,
            &[
                ("service", "SSH"),
                (
                    "reachable_scope",
                    if bind_scope == "all-interfaces" {
                        "LAN + tailnet"
                    } else {
                        "Bound network"
                    },
                ),
                (
                    "expected_policy",
                    "LAN + tailnet is intentional for recovery",
                ),
                ("policy_status", "expected"),
                ("finding", "healthy"),
                ("group", "local-network"),
            ],
        );
    } else if port == 8000 {
        let good = bind_scope == "loopback";
        assign(
            &mut result,
            &[
                ("service", "LAN Share"),
                (
                    "reachable_scope",
                    if good {
                        "Loopback only"
                    } else {
                        "LAN / broader"
                    },
                ),
                ("expected_policy", "Loopback only (127.0.0.1:8000)"),
                (
                    "policy_status",
                    if good { "expected" } else { "unexpected" },
                ),
                ("finding", if good { "healthy" } else { "critical" }),
                ("group", if good { "loopback" } else { "unexpected" }),
            ],
        );
    } else if port == 5900 {
        let address = string(entry, "address");
        let good = bind_scope == "tailnet"
            || (!address.is_empty()
                && (address == string(tailscale, "ipv4") || address == string(tailscale, "ipv6")));
        assign(
            &mut result,
            &[
                ("service", "WayVNC"),
                (
                    "reachable_scope",
                    if good {
                        "Tailnet only"
                    } else {
                        "LAN / broader"
                    },
                ),
                ("expected_policy", "Tailscale address only"),
                (
                    "policy_status",
                    if good { "expected" } else { "unexpected" },
                ),
                ("finding", if good { "healthy" } else { "critical" }),
                (
                    "group",
                    if good {
                        "private-network"
                    } else {
                        "unexpected"
                    },
                ),
            ],
        );
    } else if port == 443 && bind_scope == "tailnet" {
        assign(
            &mut result,
            &[
                ("service", "Tailscale HTTPS"),
                ("reachable_scope", "Tailnet"),
                ("expected_policy", "Private tailnet"),
                ("policy_status", "expected"),
                ("finding", "healthy"),
                ("group", "private-network"),
            ],
        );
    } else if bind_scope == "loopback" {
        assign(
            &mut result,
            &[
                ("reachable_scope", "Loopback only"),
                ("expected_policy", "Local application"),
                ("group", "loopback"),
            ],
        );
    } else if bind_scope == "tailnet" {
        assign(
            &mut result,
            &[
                ("reachable_scope", "Tailnet"),
                ("expected_policy", "Private network"),
                ("group", "private-network"),
            ],
        );
    } else if bind_scope == "all-interfaces" {
        assign(
            &mut result,
            &[
                ("reachable_scope", "LAN + other local interfaces"),
                ("expected_policy", "Unclassified all-interface listener"),
                ("policy_status", "review"),
                ("finding", "warning"),
                ("group", "other"),
            ],
        );
    } else {
        assign(
            &mut result,
            &[
                ("reachable_scope", "Bound network"),
                ("expected_policy", "Unclassified listener"),
                ("group", "other"),
            ],
        );
    }
    Some(Value::Object(result))
}

pub fn compute(input: Value) -> Option<Value> {
    let listeners = input.get("listeners")?.as_array()?;
    let tailscale = input.get("tailscale")?;
    let mut classified = Vec::with_capacity(listeners.len());
    for item in listeners {
        classified.push(classify(item, tailscale)?);
    }
    let group = |kind: &str| -> Vec<Value> {
        classified
            .iter()
            .filter(|item| string(item, "group") == kind)
            .cloned()
            .collect()
    };
    let groups = json!({
        "private_network": group("private-network"),
        "local_network": group("local-network"),
        "loopback_only": group("loopback"),
        "unexpected": group("unexpected"),
        "other": group("other"),
    });
    let public = tailscale.get("funnel")?.get("is_public")?.as_bool()?;
    let verification = string(&tailscale["funnel"], "verification");
    let verified = matches!(verification, "off" | "tailnet-only" | "public");
    let summary = if public {
        "Application-level public exposure detected"
    } else if verified {
        "No application-level public exposure detected"
    } else {
        "Application-level public exposure is not verified"
    };
    Some(json!({
        "listeners": classified,
        "unexpected_count": groups["unexpected"].as_array()?.len(),
        "groups": groups,
        "application_public_exposure_detected": public,
        "application_public_exposure_verified": verified,
        "router_nat_verified": false,
        "summary": summary,
        "router_note": "Router/NAT exposure not verified.",
    }))
}

pub fn run() -> Value {
    let mut input = Vec::new();
    if io::stdin().take(1_048_577).read_to_end(&mut input).is_err() || input.len() > 1_048_576 {
        return json!({"error": true, "message": "Exposure input is too large"});
    }
    match serde_json::from_slice::<Value>(&input)
        .ok()
        .and_then(compute)
    {
        Some(value) => value,
        None => json!({"error": true, "message": "Invalid exposure input"}),
    }
}
