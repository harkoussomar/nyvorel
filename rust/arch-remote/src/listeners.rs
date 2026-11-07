//! Read-only `ss` listener enumeration for the live exposure audit.
use regex::Regex;
use serde_json::{json, Value};
use std::process::Command;
use std::sync::LazyLock;
use std::time::Duration;

use crate::process;

static PROCESS: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r#"\(\("([^"]+)",pid=(\d+)"#).expect("fixed ss process regex"));

fn split_endpoint(endpoint: &str) -> Option<(&str, i64)> {
    let (address, port) = endpoint.trim().rsplit_once(':')?;
    if port.is_empty() || !port.bytes().all(|byte| byte.is_ascii_digit()) {
        return None;
    }
    let address = if address.starts_with('[') {
        address.strip_prefix('[')?.strip_suffix(']')?
    } else {
        address
    };
    Some((address, port.parse().ok()?))
}

fn ss(args: &[&str]) -> Option<process::Output> {
    process::run(Command::new("ss").args(args), Duration::from_secs(5))
        .ok()
        .flatten()
}

pub fn run(ipv4: &str, ipv6: &str) -> Value {
    let first = ss(&["-H", "-lntp"]);
    let output = if first.as_ref().is_some_and(|item| item.status.success()) {
        first
    } else {
        ss(&["-H", "-lnt"])
    };
    let Some(output) = output else {
        return json!([]);
    };
    let mut entries = Vec::new();
    for line in output.stdout.lines() {
        let columns: Vec<&str> = line.split_whitespace().collect();
        if columns.len() < 4 {
            continue;
        }
        let endpoint = columns[3];
        let Some((address, port)) = split_endpoint(endpoint) else {
            continue;
        };
        if port <= 0 {
            continue;
        }
        let capture = PROCESS.captures(line);
        let process = capture
            .as_ref()
            .map(|cap| cap[1].to_string())
            .unwrap_or_default();
        let pid = capture
            .as_ref()
            .and_then(|cap| cap[2].parse::<i64>().ok())
            .unwrap_or(0);
        let bind_scope = if ["127.0.0.1", "::1", "localhost"].contains(&address) {
            "loopback"
        } else if ["0.0.0.0", "::", "*"].contains(&address) {
            "all-interfaces"
        } else if (!ipv4.is_empty() && address == ipv4)
            || (!ipv6.is_empty() && address == ipv6)
            || address.starts_with("100.")
        {
            "tailnet"
        } else {
            "bound"
        };
        let scope = match bind_scope {
            "loopback" => "localhost",
            "tailnet" => "tailscale",
            other => other,
        };
        entries.push(json!({"protocol": "tcp", "address": address, "port": port,
            "endpoint": endpoint, "scope": scope, "bind_scope": bind_scope,
            "process": process, "pid": pid}));
    }
    json!(entries)
}
