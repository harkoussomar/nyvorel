use serde_json::{json, Value};
use std::{
    fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    time::Duration,
};

const THRESHOLD: &str = "/sys/class/power_supply/BAT0/charge_control_end_threshold";
const BACKENDS: [(&str, &str); 2] = [
    (
        "/usr/local/bin/nyvorel-battery-threshold",
        "/etc/nyvorel-battery-threshold",
    ),
    (
        "/usr/local/bin/ii-battery-threshold",
        "/etc/ii-battery-threshold",
    ),
];
const LIMITS: [u8; 5] = [60, 70, 80, 90, 100];

fn read_limit(path: &Path) -> Option<u8> {
    fs::read_to_string(path)
        .ok()?
        .trim()
        .parse::<u8>()
        .ok()
        .filter(|value| (1..=100).contains(value))
}

fn backend() -> Option<(PathBuf, PathBuf)> {
    BACKENDS.iter().find_map(|(helper, config)| {
        let metadata = fs::metadata(helper).ok()?;
        (metadata.is_file() && metadata.permissions().mode() & 0o111 != 0)
            .then(|| (PathBuf::from(helper), PathBuf::from(config)))
    })
}

fn status() -> Value {
    let selected = backend();
    let current = read_limit(Path::new(THRESHOLD));
    let saved = selected.as_ref().and_then(|(_, config)| read_limit(config));
    let persistent = saved.filter(|value| LIMITS.contains(value)).unwrap_or(100);
    let message = if current.is_none() {
        "Charge control is unavailable on this battery"
    } else if selected.is_none() {
        "Battery threshold helper is not installed"
    } else {
        ""
    };
    json!({
        "available": selected.is_some() && current.is_some(),
        "current": current.map(i32::from).unwrap_or(-1),
        "persistent": persistent,
        "message": message,
    })
}

pub fn run(args: &[String]) -> Result<Value, String> {
    if args == ["status"] {
        return Ok(status());
    }
    let expected = if args == ["once"] {
        100
    } else if args.len() == 2 && args[0] == "set" {
        args[1]
            .parse::<u8>()
            .ok()
            .filter(|value| LIMITS.contains(value))
            .ok_or("Allowed actions: set 60|70|80|90|100, once")?
    } else {
        return Err("Allowed actions: set 60|70|80|90|100, once".into());
    };
    let selected = backend();
    if selected.is_none() || read_limit(Path::new(THRESHOLD)).is_none() {
        return Err(status()["message"]
            .as_str()
            .unwrap_or("Charge control unavailable")
            .into());
    }
    let (helper, _) = selected.unwrap();
    let helper = helper.to_str().ok_or("Invalid battery helper path")?;
    let mut command = vec!["/usr/bin/sudo", "-n", helper, args[0].as_str()];
    if args.len() == 2 {
        command.push(args[1].as_str());
    }
    let (code, _, stderr) = crate::command(&command, Duration::from_secs(15))?;
    if code != 0 {
        return Err(if stderr.trim().is_empty() {
            "Battery threshold change failed".into()
        } else {
            stderr.trim().into()
        });
    }
    let state = status();
    let current = state["current"].as_i64().unwrap_or(-1);
    let persistent = state["persistent"].as_i64().unwrap_or(-1);
    if current != i64::from(expected) || (args[0] == "set" && persistent != i64::from(expected)) {
        return Err("Battery threshold did not match the requested value".into());
    }
    Ok(state)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_unlisted_limits_and_actions() {
        for args in [["set", "50"], ["set", "80;touch /tmp/x"], ["reset", "80"]] {
            let args: Vec<String> = args.iter().map(|value| value.to_string()).collect();
            assert!(run(&args).is_err());
        }
    }
}
