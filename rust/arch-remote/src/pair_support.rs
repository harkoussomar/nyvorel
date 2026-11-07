//! Capability discovery only: call help paths, never the token-minting pair command.
use crate::process;
use regex::Regex;
use serde_json::{json, Value};
use std::process::Command;
use std::time::Duration;

pub fn run(binary: &str) -> Value {
    if binary.is_empty() {
        return json!({"installed": false, "available": false, "cancel_supported": false,
            "binary": "", "status": "missing", "reason": "LAN Share is not installed.",
            "source": "explicit executable discovery"});
    }
    let pair = process::run(
        Command::new(binary).args(["pair", "--help"]),
        Duration::from_secs(4),
    );
    let (success, help) = match pair {
        Ok(Some(output)) => (
            output.status.success(),
            format!("{}\n{}", output.stdout, output.stderr),
        ),
        _ => (false, "\n".into()),
    };
    let mut lower = help.to_lowercase();
    let mut available = success || help.contains("--json") || lower.contains("pair");
    if !available {
        let top = process::run(Command::new(binary).arg("--help"), Duration::from_secs(4));
        let (top_success, top_text) = match top {
            Ok(Some(output)) => (
                output.status.success(),
                format!("{}\n{}", output.stdout, output.stderr),
            ),
            _ => (false, "\n".into()),
        };
        let top_lower = top_text.to_lowercase();
        let marker = Regex::new(r"(^|[\s,{])pair([\s,}]|$)").expect("static regular expression");
        available = top_success && marker.is_match(&top_lower);
        if !top_lower.is_empty() {
            lower.push('\n');
            lower.push_str(&top_lower);
        }
    }
    json!({"installed": true, "available": available, "cancel_supported": lower.contains("--cancel"),
        "binary": binary, "status": if available {"supported"} else {"unsupported"},
        "reason": if available {"QR pairing is supported."} else {"Installed LAN Share version does not support QR pairing."},
        "source": format!("{binary} pair --help")})
}
