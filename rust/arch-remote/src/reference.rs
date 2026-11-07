//! On-demand operational reference. Static entries are reviewed JSON data;
//! only state-dependent fields are derived at runtime. Never include credentials.
use serde_json::{json, Value};
use std::io::{self, Read};

fn yes(value: &Value) -> bool {
    crate::py_truthy(Some(value))
}
fn text(value: &Value) -> &str {
    value.as_str().unwrap_or("")
}
fn chosen<'a>(values: impl IntoIterator<Item = &'a Value>) -> &'a str {
    values
        .into_iter()
        .map(text)
        .find(|item| !item.is_empty())
        .unwrap_or("")
}
fn python_string(value: &Value) -> String {
    match value {
        Value::String(s) => s.clone(),
        Value::Bool(true) => "True".into(),
        Value::Bool(false) => "False".into(),
        Value::Null => "None".into(),
        _ => value.to_string(),
    }
}
fn entry<'a>(sections: &'a mut Value, id: &str) -> Option<&'a mut Value> {
    sections
        .as_array_mut()?
        .iter_mut()
        .flat_map(|section| section["entries"].as_array_mut().into_iter().flatten())
        .find(|item| item["id"] == id)
}
fn set(sections: &mut Value, id: &str, field: &str, value: Value) -> Option<()> {
    entry(sections, id)?[field] = value;
    Some(())
}
fn state_label(running: bool, ready: bool) -> &'static str {
    if ready {
        "Ready"
    } else if running {
        "Running · not ready"
    } else {
        "Expected off"
    }
}

pub fn derive(input: &Value) -> Option<Value> {
    let state = &input["state"];
    let phone = &state["phone_guide"];
    let tailscale = &state["tailscale"];
    let services = &state["services"];
    let wake = &state["wake"];
    let host = chosen([
        &phone["host"],
        &tailscale["dns_name"],
        &tailscale["hostname"],
        &state["host"]["hostname"],
    ]);
    let share_url = text(&phone["share"]["url"]);
    let vnc_fallback = if host.is_empty() {
        String::new()
    } else {
        format!("{host}:5900")
    };
    let vnc_endpoint = chosen([&phone["vnc"]["endpoint"], &json!(vnc_fallback)]).to_owned();
    let fingerprint = text(&phone["sftp"]["fingerprint"]);
    let user = chosen([&phone["user"], &input["user"]]);
    let root_path = chosen([&phone["sftp"]["root_path"], &input["home"]]);
    let home = text(&input["home"]);
    let wifi_phy = text(&wake["wifi"]["phy"]);
    let ethernet_if = text(&wake["ethernet"]["interface_name"]);
    let share_running = yes(&services["lan_share"]["running"]);
    let share_ready = yes(&services["lan_share"]["ready"]);
    let desktop_running = yes(&services["wayvnc"]["running"]);
    let desktop_ready = yes(&services["wayvnc"]["ready"]);
    let share_state = state_label(share_running, share_ready);
    let desktop_state = state_label(desktop_running, desktop_ready);
    let mut sections: Value = serde_json::from_str(include_str!("reference_template.json")).ok()?;

    set(
        &mut sections,
        "phone-share-on",
        "command",
        json!(if share_running {
            "archctl share-off"
        } else {
            "archctl share-on"
        }),
    )?;
    set(
        &mut sections,
        "phone-share-on",
        "current_state",
        json!(share_state),
    )?;
    set(
        &mut sections,
        "phone-share-on",
        "action_args",
        json!([
            "service",
            "lan-share",
            if share_running { "stop" } else { "start" }
        ]),
    )?;
    set(
        &mut sections,
        "phone-share-on",
        "action_label",
        json!(if share_running {
            "Stop now"
        } else {
            "Start now"
        }),
    )?;
    set(
        &mut sections,
        "phone-desktop-on",
        "command",
        json!(if desktop_running {
            "archctl desktop-off"
        } else {
            "archctl desktop-on"
        }),
    )?;
    set(
        &mut sections,
        "phone-desktop-on",
        "current_state",
        json!(desktop_state),
    )?;
    set(
        &mut sections,
        "phone-desktop-on",
        "action_args",
        json!([
            "service",
            "wayvnc-remote",
            if desktop_running { "stop" } else { "start" }
        ]),
    )?;
    set(
        &mut sections,
        "phone-desktop-on",
        "action_label",
        json!(if desktop_running {
            "Stop now"
        } else {
            "Start now"
        }),
    )?;

    let host_display = if host.is_empty() {
        "Not detected"
    } else {
        host
    };
    set(&mut sections, "voyager-client", "value", json!(format!(
        "Protocol: SFTP\nHost: {host_display}\nPort: 22\nUser: {user}\nRoot: {root_path}\nAuthentication: Voyager's own SSH keypair")))?;
    set(&mut sections, "share-url", "value", json!(share_url))?;
    set(
        &mut sections,
        "share-url",
        "copyable",
        json!(!share_url.is_empty()),
    )?;
    set(
        &mut sections,
        "share-url",
        "current_state",
        json!(share_state),
    )?;
    let endpoint_display = if vnc_endpoint.is_empty() {
        "Not detected"
    } else {
        &vnc_endpoint
    };
    let auth_mode = text(&services["wayvnc"]["auth_mode"]);
    let auth_mode = if auth_mode.is_empty() {
        "unverified"
    } else {
        auth_mode
    };
    let auth_user = text(&services["wayvnc"]["auth_username"]);
    let auth_user = if auth_user.is_empty() {
        "not configured"
    } else {
        auth_user
    };
    set(&mut sections, "avnc-config", "value", json!(format!(
        "Host: {host_display}\nPort: 5900\nEndpoint: {endpoint_display}\nAuthentication: {auth_mode}\nUsername: {auth_user}\nPassword: retrieve locally from ~/.config/wayvnc/arch-remote.conf")))?;
    set(
        &mut sections,
        "avnc-config",
        "copyable",
        json!(!vnc_endpoint.is_empty()),
    )?;
    set(
        &mut sections,
        "avnc-config",
        "current_state",
        json!(desktop_state),
    )?;
    set(&mut sections, "ssh-policy", "value", json!(format!(
        "PermitRootLogin no\nPubkeyAuthentication yes\nPasswordAuthentication no\nKbdInteractiveAuthentication no\nAllowUsers {user}")))?;
    set(
        &mut sections,
        "ssh-fingerprint",
        "value",
        json!(fingerprint),
    )?;
    set(
        &mut sections,
        "ssh-fingerprint",
        "copyable",
        json!(!fingerprint.is_empty()),
    )?;
    let ssh_config = text(&phone["ssh_config"]);
    set(
        &mut sections,
        "ssh-termux-config",
        "value",
        json!(ssh_config),
    )?;
    set(
        &mut sections,
        "ssh-termux-config",
        "copyable",
        json!(!ssh_config.is_empty()),
    )?;

    for (id, tail) in [
        ("cfg-wayvnc-launcher", ".local/bin/wayvnc-remote"),
        (
            "cfg-wayvnc-service",
            ".config/systemd/user/wayvnc-remote.service",
        ),
        (
            "cfg-share-service",
            ".config/systemd/user/lan-share.service",
        ),
        ("cfg-share-app", ".local/share/lan-share/app.py"),
        ("cfg-controller", ".local/bin/arch-remote"),
    ] {
        set(&mut sections, id, "value", json!(format!("{home}/{tail}")))?;
    }
    if wifi_phy.is_empty() || ethernet_if.is_empty() {
        let missing: Value = serde_json::from_str(include_str!("reference_missing.json")).ok()?;
        let power = sections
            .as_array_mut()?
            .iter_mut()
            .find(|section| section["id"] == "power")?;
        let entries = power["entries"].as_array_mut()?;
        if wifi_phy.is_empty() {
            entries[0] = missing[0].clone();
        }
        if ethernet_if.is_empty() {
            entries[1] = missing[1].clone();
        }
    }
    if !wifi_phy.is_empty() {
        set(
            &mut sections,
            "wowlan-show",
            "command",
            json!(format!("iw phy {wifi_phy} wowlan show")),
        )?;
    }
    if !ethernet_if.is_empty() {
        set(
            &mut sections,
            "wol-show",
            "command",
            json!(format!("sudo ethtool {ethernet_if}")),
        )?;
    }
    set(
        &mut sections,
        "linger-show",
        "command",
        json!(format!("loginctl show-user {user} -p Linger")),
    )?;
    let lid_status = if yes(&state["lid"]["status"]) {
        python_string(&state["lid"]["status"])
    } else {
        "unknown".into()
    };
    set(
        &mut sections,
        "lid-policy",
        "current_state",
        json!(lid_status),
    )?;

    let serialized = serde_json::to_string(&sections).ok()?;
    if ["/pair#t=", "authkey-", "session_cookie", "pair_url"]
        .iter()
        .any(|token| serialized.contains(token))
    {
        return None;
    }
    Some(
        json!({"ok": true, "schema_version": 1, "generated_at": crate::now(),
        "snapshot_generation": state["generation"].as_i64().unwrap_or(0),
        "dynamic": {"tailscale_hostname": host, "tailscale_ip": text(&tailscale["ipv4"]),
            "serve_url": share_url, "vnc_endpoint": vnc_endpoint,
            "ssh_fingerprint": fingerprint, "wifi_phy": wifi_phy,
            "ethernet_interface": ethernet_if, "user": user},
        "sections": sections}),
    )
}

pub fn run() -> Value {
    let mut bytes = Vec::new();
    if io::stdin().take(2_097_153).read_to_end(&mut bytes).is_err() || bytes.len() > 2_097_152 {
        return json!({"error": true, "message": "Reference input is too large"});
    }
    serde_json::from_slice::<Value>(&bytes)
        .ok()
        .and_then(|input| derive(&input))
        .unwrap_or_else(|| json!({"error": true, "message": "Invalid or unsafe reference model"}))
}
