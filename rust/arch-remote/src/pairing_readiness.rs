//! Pure pairing gate. No credential is created or retained by this module.
use regex::Regex;
use serde_json::{json, Value};
use std::io::{self, Read};
use url::Url;

fn yes(value: &Value) -> bool {
    crate::py_truthy(Some(value))
}

fn text(value: &Value) -> &str {
    value.as_str().unwrap_or("")
}

fn private_verified(serve: &Value, funnel: &Value) -> bool {
    yes(&serve["configured"])
        && serve["tailnet_only"] == true
        && serve["verification"] == "tailnet-only"
        && (funnel["verification"] == "off" || funnel["verification"] == "tailnet-only")
        && !yes(&funnel["is_public"])
}

fn safe_url(value: &str, verified: bool) -> String {
    if !verified || value.is_empty() {
        return String::new();
    }
    let Ok(url) = Url::parse(value) else {
        return String::new();
    };
    let Some(host) = url.host_str() else {
        return String::new();
    };
    if url.scheme() != "https"
        || !host.ends_with(".ts.net")
        || !url.username().is_empty()
        || url.password().is_some_and(|password| !password.is_empty())
        || url.query().is_some_and(|query| !query.is_empty())
        || url.fragment().is_some_and(|fragment| !fragment.is_empty())
    {
        return String::new();
    }
    format!("https://{host}{}", url.path())
}

fn port(value: &Value) -> i64 {
    value
        .as_i64()
        .or_else(|| value.as_str()?.parse().ok())
        .unwrap_or(0)
}

pub fn derive(input: &Value) -> Value {
    let state = &input["state"];
    let support = &input["support"];
    let share = &state["services"]["lan_share"];
    let serve = &state["tailscale"]["serve"];
    let funnel = &state["tailscale"]["funnel"];
    let verified = private_verified(serve, funnel);
    let url = safe_url(text(&serve["url"]), verified);
    let listeners = share["listeners"].as_array();
    let listener_ok = listeners.is_some_and(|items| {
        !items.is_empty()
            && items.iter().all(|item| {
                ["127.0.0.1", "::1", "localhost"].contains(&text(&item["address"]))
                    && port(&item["port"]) == 8000
            })
    });
    let upstream = text(&serve["upstream"]);
    let upstream_ok = Regex::new(r"^https?://(?:127\.0\.0\.1|localhost|\[::1\]):8000(?:/|$)")
        .expect("static regular expression")
        .is_match(upstream);
    let service_ready = yes(&share["ready"]);
    let serve_configured = yes(&serve["configured"]);
    let serve_private = serve["tailnet_only"] == true && serve["verification"] == "tailnet-only";
    let funnel_private = ["off", "tailnet-only"].contains(&text(&funnel["verification"]))
        && !yes(&funnel["is_public"]);
    let qrencode = yes(&input["qrencode_available"]);
    let pair_executable = yes(&support["installed"]);
    let pair_supported = yes(&support["available"]);
    let checks = json!({
        "service_ready": service_ready, "listener_ready": listener_ok,
        "serve_configured": serve_configured, "serve_tailnet_only": serve_private,
        "funnel_private_verified": funnel_private, "private_exposure_verified": verified,
        "serve_url_safe": !url.is_empty(), "upstream_is_lan_share": upstream_ok,
        "qrencode_available": qrencode, "pair_executable_found": pair_executable,
        "pair_command_supported": pair_supported,
    });
    let available = checks
        .as_object()
        .is_some_and(|checks| checks.values().all(|value| value == true));
    let reason = if !service_ready {
        "LAN Share is not ready."
    } else if !listener_ok {
        "The expected loopback listener 127.0.0.1:8000 is not healthy."
    } else if !serve_configured {
        "No Tailscale Serve route is configured."
    } else if !serve_private {
        "Tailscale Serve is not positively verified as tailnet-only."
    } else if !funnel_private {
        "Pairing is blocked until Funnel exposure is positively verified private/off."
    } else if !verified || url.is_empty() {
        "Private Tailscale exposure could not be verified."
    } else if !upstream_ok {
        "Tailscale Serve is not proxying to LAN Share on localhost:8000."
    } else if !pair_executable {
        "LAN Share is not installed."
    } else if !pair_supported {
        "Installed LAN Share version does not support QR pairing."
    } else if !qrencode {
        "QR encoder is unavailable."
    } else {
        "Ready for one-scan pairing."
    };
    json!({"available": available, "reason": reason, "checks": checks, "serve_url": url,
        "pair_binary": text(&support["binary"]),
        "pair_support_status": support["status"].as_str().filter(|value| !value.is_empty()).unwrap_or("missing")})
}

pub fn run() -> Value {
    let mut input = Vec::new();
    if io::stdin().take(2_097_152).read_to_end(&mut input).is_err() {
        return json!({"error": true, "message": "Could not read pairing evidence"});
    }
    let Ok(input) = serde_json::from_slice::<Value>(&input) else {
        return json!({"error": true, "message": "Invalid pairing evidence"});
    };
    derive(&input)
}
