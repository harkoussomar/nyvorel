//! Human-readable arch-remote CLI without a Python interpreter.
use serde_json::Value;

use crate::{native_snapshot, operation, operation_status};

fn text(value: &Value) -> &str {
    value.as_str().unwrap_or("")
}
fn yes(value: &Value) -> bool {
    value == true
}

pub fn run(args: &[String]) -> i32 {
    let command = args.first().map(String::as_str).unwrap_or("status");
    if command == "status" {
        let state = native_snapshot::run(false);
        if state["error"] == true {
            eprintln!("{}", text(&state["message"]));
            return 1;
        }
        let services = &state["services"];
        let tailnet = &state["tailscale"];
        let health = &state["health"];
        let label = |key: &str| {
            let service = &services[key];
            if yes(&service["ready"]) {
                "ready"
            } else if yes(&service["running"]) {
                "running"
            } else {
                "off"
            }
        };
        println!("\n╭──────────────────────────────────────╮");
        println!("│          ARCH REMOTE STATUS          │");
        println!("╰──────────────────────────────────────╯\n");
        println!("Health        : {}", text(&health["label"]));
        println!(
            "Tailscale     : {}",
            if yes(&tailnet["connected"]) {
                "connected"
            } else {
                text(&tailnet["backend_state"])
            }
        );
        println!(
            "SSH           : {}",
            if yes(&services["sshd"]["ready"]) {
                "ready"
            } else {
                text(&services["sshd"]["readiness"])
            }
        );
        println!("LAN Share     : {}", label("lan_share"));
        println!("Remote Desktop: {}", label("wayvnc"));
        println!(
            "Tailscale IP  : {}",
            if text(&tailnet["ipv4"]).is_empty() {
                "—"
            } else {
                text(&tailnet["ipv4"])
            }
        );
        println!(
            "Contract      : {} / {}\n",
            text(&state["ui_contract"]),
            text(&state["backend_revision"])
        );
        return 0;
    }
    if command == "operation" {
        println!("{}", operation_status(""));
        return 0;
    }
    let action: Vec<String> = match command {
        "share-on" => vec!["service", "lan-share", "start"],
        "share-off" => vec!["service", "lan-share", "stop"],
        "share-restart" => vec!["service", "lan-share", "restart"],
        "desktop-on" => vec!["service", "wayvnc-remote", "start"],
        "desktop-off" => vec!["service", "wayvnc-remote", "stop"],
        "desktop-restart" => vec!["service", "wayvnc-remote", "restart"],
        "lockdown" => vec!["lockdown"],
        _ => {
            eprintln!("Usage: arch-remote status|share-on|share-off|share-restart|desktop-on|desktop-off|desktop-restart|lockdown|operation");
            return 2;
        }
    }.into_iter().map(str::to_string).collect();
    let started = operation::start_native(&action);
    if started["ok"] != true {
        eprintln!("{}", text(&started["message"]));
        return 1;
    }
    let id = text(&started["operation"]["id"]);
    if id.is_empty() {
        eprintln!("Operation did not return an ID.");
        return 1;
    }
    let final_state = operation::wait(&[id.into(), "60".into()]);
    let message = text(&final_state["operation"]["message"]);
    if !message.is_empty() {
        println!("{message}");
    }
    if final_state["error"] == true || final_state["operation"]["status"] == "failed" {
        1
    } else {
        0
    }
}
