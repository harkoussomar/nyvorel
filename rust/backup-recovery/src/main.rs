use serde_json::{json, Map, Value};
use std::collections::{HashMap, HashSet};
use std::fs::{self, OpenOptions};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const STATE_FILE: &str = "/var/lib/backup-recovery/state.json";
const ACTION_STATE_FILE: &str = "/var/lib/backup-recovery/action-state.json";
const UI_CONTRACT: &str = "1.6.0";
const SCHEMA_VERSION: i64 = 2;
const STATE_STALE_SECONDS: i64 = 1800;
const ACTION_UNITS: &[(&str, &str)] = &[
    ("backup", "backup-recovery-backup.service"),
    ("timeshift", "backup-recovery-timeshift.service"),
    ("restic-check", "backup-recovery-restic-check.service"),
    ("restore-test", "backup-recovery-restore-test.service"),
    ("smart-short", "backup-recovery-smart-short.service"),
    ("smart-long", "backup-recovery-smart-long.service"),
    ("mount", "backup-recovery-mount.service"),
    ("eject", "backup-recovery-eject.service"),
    (
        "refresh-manifests",
        "backup-recovery-refresh-manifests.service",
    ),
];
const EXTERNAL_BUSY_UNITS: &[(&str, &str)] = &[
    ("external-backup", "restic-system-backup.service"),
    ("external-maintenance", "restic-maintenance.service"),
];

struct Output {
    code: i32,
    stdout: String,
    stderr: String,
}

fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |duration| duration.as_secs() as i64)
}

// Children are bounded and reaped; readers prevent a full pipe from blocking a child.
fn run(program: &str, args: &[&str], timeout: Duration) -> Output {
    let child = Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn();
    let Ok(mut child) = child else {
        return Output {
            code: 124,
            stdout: String::new(),
            stderr: child
                .err()
                .map_or_else(String::new, |error| error.to_string()),
        };
    };
    let stdout = child.stdout.take().expect("piped stdout");
    let stderr = child.stderr.take().expect("piped stderr");
    let stdout_reader = thread::spawn(move || {
        let mut bytes = Vec::new();
        let _ = stdout.take(16 * 1024 * 1024).read_to_end(&mut bytes);
        String::from_utf8_lossy(&bytes).into_owned()
    });
    let stderr_reader = thread::spawn(move || {
        let mut bytes = Vec::new();
        let _ = stderr.take(1024 * 1024).read_to_end(&mut bytes);
        String::from_utf8_lossy(&bytes).into_owned()
    });
    let deadline = std::time::Instant::now() + timeout;
    let code = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status.code().unwrap_or(1),
            Ok(None) if std::time::Instant::now() < deadline => {
                thread::sleep(Duration::from_millis(20));
            }
            Ok(None) => {
                let _ = child.kill();
                let _ = child.wait();
                break 124;
            }
            Err(_) => {
                let _ = child.kill();
                let _ = child.wait();
                break 124;
            }
        }
    };
    Output {
        code,
        stdout: stdout_reader.join().unwrap_or_default(),
        stderr: stderr_reader.join().unwrap_or_default(),
    }
}

fn empty_unit_state(unit: &str) -> Value {
    json!({
        "unit": unit, "load_state": "unknown", "active_state": "unknown",
        "sub_state": "unknown", "result": "unknown", "exec_main_status": null
    })
}

fn parse_unit_states(text: &str, units: &[&str]) -> Map<String, Value> {
    let mut result: Map<String, Value> = units
        .iter()
        .map(|unit| ((*unit).to_owned(), empty_unit_state(unit)))
        .collect();
    let mut block: HashMap<&str, &str> = HashMap::new();
    let flush = |block: &mut HashMap<&str, &str>, result: &mut Map<String, Value>| {
        if let Some(unit) = block.get("Id") {
            if let Some(data) = result.get_mut(*unit).and_then(Value::as_object_mut) {
                for (key, field) in [
                    ("LoadState", "load_state"),
                    ("ActiveState", "active_state"),
                    ("SubState", "sub_state"),
                    ("Result", "result"),
                    ("ActiveEnterTimestamp", "active_enter_timestamp"),
                    ("InactiveEnterTimestamp", "inactive_enter_timestamp"),
                ] {
                    if let Some(value) = block.get(key) {
                        data.insert(field.into(), json!(value));
                    }
                }
                if let Some(value) = block.get("ExecMainStatus") {
                    data.insert(
                        "exec_main_status".into(),
                        value.parse::<i64>().map_or(Value::Null, |n| json!(n)),
                    );
                }
            }
        }
        block.clear();
    };
    for line in text.lines() {
        if line.trim().is_empty() {
            flush(&mut block, &mut result);
        } else if let Some((key, value)) = line.split_once('=') {
            if key == "Id" && !block.is_empty() {
                flush(&mut block, &mut result);
            }
            block.insert(key, value);
        }
    }
    flush(&mut block, &mut result);
    result
}

fn unit_states(units: &[&str]) -> Map<String, Value> {
    let mut unique = Vec::new();
    let mut seen = HashSet::new();
    for unit in units {
        if seen.insert(*unit) {
            unique.push(*unit);
        }
    }
    let args: Vec<&str> = std::iter::once("show")
        .chain(unique.iter().copied())
        .chain([UNIT_PROPERTIES_ARG, "--no-pager"])
        .collect();
    let output = run("systemctl", &args, Duration::from_secs(6));
    parse_unit_states(if output.code == 0 { &output.stdout } else { "" }, &unique)
}

const UNIT_PROPERTIES_ARG: &str =
    "--property=Id,LoadState,ActiveState,SubState,Result,ExecMainStatus,ActiveEnterTimestamp,InactiveEnterTimestamp";

fn dotfiles_empty() -> Value {
    json!({"available": false, "clean": false, "changed_count": null, "latest": null})
}

fn home() -> PathBuf {
    std::env::var_os("HOME").map_or_else(|| PathBuf::from("/"), PathBuf::from)
}

fn cache_path() -> PathBuf {
    home().join(".cache/backup-recovery/dotfiles-state.json")
}

fn dotfiles_state() -> Value {
    let home = home();
    let git_dir = home.join(".dotfiles");
    if !git_dir.exists() {
        return dotfiles_empty();
    }
    let git_dir_arg = format!("--git-dir={}", git_dir.display());
    let work_tree_arg = format!("--work-tree={}", home.display());
    let status = run(
        "git",
        &[&git_dir_arg, &work_tree_arg, "status", "--porcelain"],
        Duration::from_secs(8),
    );
    let log = run(
        "git",
        &[
            &git_dir_arg,
            &work_tree_arg,
            "log",
            "-1",
            "--format=%H%x1f%h%x1f%ct%x1f%s",
        ],
        Duration::from_secs(8),
    );
    let latest = if log.code == 0 {
        let parts: Vec<&str> = log.stdout.trim().splitn(4, '\u{1f}').collect();
        if parts.len() == 4 {
            json!({
                "id": parts[0], "short_id": parts[1],
                "timestamp": parts[2].parse::<i64>().unwrap_or(0),
                "subject": parts[3],
            })
        } else {
            Value::Null
        }
    } else {
        Value::Null
    };
    let count = status
        .stdout
        .lines()
        .filter(|line| !line.trim().is_empty())
        .count();
    json!({
        "available": status.code == 0,
        "clean": status.code == 0 && count == 0,
        "changed_count": if status.code == 0 { json!(count) } else { Value::Null },
        "latest": latest,
    })
}

fn read_object(path: &Path) -> Option<Value> {
    let data = fs::read(path).ok()?;
    let value: Value = serde_json::from_slice(&data).ok()?;
    value.is_object().then_some(value)
}

fn read_dotfiles_cache() -> Value {
    read_object(&cache_path()).unwrap_or_else(dotfiles_empty)
}

fn refresh_dotfiles_cache() -> Value {
    let state = dotfiles_state();
    let path = cache_path();
    if let Some(parent) = path.parent() {
        if fs::create_dir_all(parent).is_ok() {
            let temp = path.with_file_name(format!(
                ".dotfiles-state-{}-{}.tmp",
                std::process::id(),
                now()
            ));
            #[cfg(unix)]
            use std::os::unix::fs::OpenOptionsExt;
            let mut options = OpenOptions::new();
            options.write(true).create_new(true);
            #[cfg(unix)]
            options.mode(0o600);
            if let Ok(mut file) = options.open(&temp) {
                let saved = serde_json::to_vec(&state)
                    .ok()
                    .and_then(|mut bytes| {
                        bytes.push(b'\n');
                        file.write_all(&bytes).ok()
                    })
                    .and_then(|_| file.sync_all().ok())
                    .is_some();
                drop(file);
                if saved {
                    if fs::rename(&temp, &path).is_err() {
                        let _ = fs::remove_file(&temp);
                    }
                } else {
                    let _ = fs::remove_file(&temp);
                }
            }
        }
    }
    state
}

fn fallback_state(message: &str) -> Value {
    let mut data: Value = serde_json::from_str(include_str!("../fallback-state.json"))
        .expect("bundled fallback state");
    data["overall"]["summary"] = json!(message);
    data["state_health"]["error"] = json!(message);
    data
}

fn integer(value: &Value) -> i64 {
    value
        .as_i64()
        .or_else(|| value.as_str().and_then(|s| s.parse::<i64>().ok()))
        .unwrap_or(0)
}

fn contract_error(data: &Value) -> Option<String> {
    let schema = data["schema_version"]
        .as_i64()
        .or_else(|| data["schema_version"].as_str().and_then(|s| s.parse().ok()))
        .unwrap_or(-1);
    if schema != SCHEMA_VERSION {
        return Some(format!(
            "Incompatible state schema: expected {SCHEMA_VERSION}, got {schema}."
        ));
    }
    let contract = data["ui_contract"].as_str().unwrap_or_default();
    (contract != UI_CONTRACT).then(|| {
        format!(
            "Incompatible UI contract: expected {UI_CONTRACT}, got {}.",
            if contract.is_empty() {
                "missing"
            } else {
                contract
            }
        )
    })
}

fn decorate_state_health(data: &mut Value, refresh: Option<Result<(), String>>) {
    let generated = integer(&data["generated_at"]);
    let age = (generated != 0).then(|| (now() - generated).max(0));
    let fresh = age.is_some_and(|age| age <= STATE_STALE_SECONDS);
    let contract = contract_error(data);
    let error = refresh
        .as_ref()
        .and_then(|result| result.as_ref().err().cloned())
        .or_else(|| contract.clone())
        .unwrap_or_default();
    data["state_health"] = json!({
        "compatible": contract.is_none(), "fresh": fresh, "age_seconds": age,
        "refresh_ok": refresh.as_ref().map(Result::is_ok),
        "error": error, "stale_after_seconds": STATE_STALE_SECONDS,
    });
    if let Some(message) = contract {
        data["overall"] = json!({
            "status": "critical", "label": "Incompatible", "summary": message,
        });
    } else if refresh.as_ref().is_some_and(Result::is_err) {
        data["overall"] = json!({
            "status": "unverified", "label": "State stale",
            "summary": "The latest privileged state refresh failed; displayed evidence is last-known only.",
        });
    } else if !fresh {
        data["overall"] = json!({
            "status": "unverified", "label": "State stale",
            "summary": "Backup state has not been refreshed recently enough to claim current protection.",
        });
    }
}

fn all_units() -> Vec<(&'static str, &'static str)> {
    ACTION_UNITS
        .iter()
        .chain(EXTERNAL_BUSY_UNITS.iter())
        .copied()
        .collect()
}

fn running(name: &str, states: &Map<String, Value>, unit: &str) -> bool {
    let _ = name;
    matches!(
        states[unit]["active_state"].as_str(),
        Some("active" | "activating")
    )
}

fn decorate_operation(data: &mut Value, running_names: &[&str]) {
    let current = running_names.first().copied().unwrap_or("");
    let raw = read_object(Path::new(ACTION_STATE_FILE)).unwrap_or_else(|| json!({}));
    let mut op = json!({
        "running": !running_names.is_empty(), "action": current,
        "state": if running_names.is_empty() {
            raw["state"].as_str().filter(|s| !s.is_empty()).unwrap_or("idle")
        } else { "running" },
        "phase": "", "started_at": 0, "updated_at": 0, "finished_at": 0,
        "elapsed_seconds": 0, "progress": {}, "message": "",
    });
    let raw_action = raw["action"].as_str().unwrap_or("");
    if raw.as_object().is_some_and(|map| !map.is_empty())
        && (current.is_empty() || raw_action == current)
    {
        if let Some(fields) = raw.as_object() {
            for (key, value) in fields {
                op[key] = value.clone();
            }
        }
        op["running"] = json!(!running_names.is_empty());
    } else if !current.is_empty() {
        op["action"] = json!(current);
        op["phase"] = json!("Operation in progress");
    }
    let started = integer(&op["started_at"]);
    if started != 0 {
        let end = if op["running"] == true {
            now()
        } else {
            let finished = integer(&op["finished_at"]);
            if finished != 0 {
                finished
            } else {
                let updated = integer(&op["updated_at"]);
                if updated != 0 {
                    updated
                } else {
                    now()
                }
            }
        };
        op["elapsed_seconds"] = json!((end - started).max(0));
    }
    if !op["progress"].is_object() {
        op["progress"] = json!({});
    }
    data["operation"] = op;
    data["current_action"] = json!(current);
    data["action_running"] = json!(!running_names.is_empty());
}

fn load_state(instant: bool, refresh_dotfiles: bool) -> Value {
    let mut data = match fs::read_to_string(STATE_FILE) {
        Ok(text) => match serde_json::from_str::<Value>(&text) {
            Ok(value) if value.is_object() => value,
            Ok(_) => fallback_state("State unavailable: state root is not an object"),
            Err(error) => fallback_state(&format!("State unavailable: {error}")),
        },
        Err(error) => fallback_state(&format!("State unavailable: {error}")),
    };
    if let Some(message) = contract_error(&data) {
        let schema = data["schema_version"].clone();
        let contract = data["ui_contract"].clone();
        data = fallback_state(&message);
        data["schema_version"] = schema;
        data["ui_contract"] = contract;
    }
    if !data["history"].is_object() {
        data["history"] = json!({});
    }
    data["history"]["dotfiles"] = if refresh_dotfiles {
        refresh_dotfiles_cache()
    } else {
        read_dotfiles_cache()
    };
    if instant {
        let raw = read_object(Path::new(ACTION_STATE_FILE)).unwrap_or_else(|| json!({}));
        let is_running = raw["state"] == "running";
        let name = raw["action"]
            .as_str()
            .filter(|s| !s.is_empty())
            .unwrap_or("operation");
        data["actions"] = json!({});
        data["external_actions"] = json!({});
        let running_names = if is_running { vec![name] } else { Vec::new() };
        decorate_operation(&mut data, &running_names);
        data["snapshot_mode"] = json!("instant-cache");
    } else {
        let all = all_units();
        let units: Vec<&str> = all.iter().map(|(_, unit)| *unit).collect();
        let states = unit_states(&units);
        let mut actions = Map::new();
        let mut external = Map::new();
        let mut running_names = Vec::new();
        for (name, unit) in ACTION_UNITS {
            actions.insert(
                (*name).into(),
                states
                    .get(*unit)
                    .cloned()
                    .unwrap_or_else(|| empty_unit_state(unit)),
            );
            if running(name, &states, unit) {
                running_names.push(*name);
            }
        }
        for (name, unit) in EXTERNAL_BUSY_UNITS {
            external.insert(
                (*name).into(),
                states
                    .get(*unit)
                    .cloned()
                    .unwrap_or_else(|| empty_unit_state(unit)),
            );
            if running(name, &states, unit) {
                running_names.push(*name);
            }
        }
        data["actions"] = Value::Object(actions);
        data["external_actions"] = Value::Object(external);
        decorate_operation(&mut data, &running_names);
        data["snapshot_mode"] = json!("fast-live");
    }
    decorate_state_health(&mut data, None);
    data
}

fn refresh_state() -> Result<(), String> {
    let availability = run(
        "systemctl",
        &[
            "show",
            "backup-recovery-state.service",
            "--property=LoadState",
            "--value",
        ],
        Duration::from_secs(6),
    );
    if availability.code != 0 || availability.stdout.trim() != "loaded" {
        return Err("Backup & Recovery system service is not installed; privileged refresh is unavailable on this machine.".into());
    }
    let output = run(
        "systemctl",
        &["start", "backup-recovery-state.service"],
        Duration::from_secs(45),
    );
    if output.code == 0 {
        Ok(())
    } else {
        let detail = if output.stderr.is_empty() {
            &output.stdout
        } else {
            &output.stderr
        };
        let detail = detail.trim();
        Err(if detail.is_empty() {
            "Unable to refresh privileged state.".into()
        } else {
            detail.into()
        })
    }
}

fn action(name: &str) -> Value {
    let Some((_, unit)) = ACTION_UNITS.iter().find(|(action, _)| *action == name) else {
        return json!({
            "ok": false, "error": "unknown-action", "message": format!("Unknown action: {name}"),
        });
    };
    let all = all_units();
    let units: Vec<&str> = all.iter().map(|(_, unit)| *unit).collect();
    let states = unit_states(&units);
    if let Some((current, current_unit)) = all
        .iter()
        .find(|(current, unit)| running(current, &states, unit))
    {
        let title = current
            .split('-')
            .map(|word| {
                let mut chars = word.chars();
                chars.next().map_or_else(String::new, |first| {
                    first.to_uppercase().collect::<String>() + chars.as_str()
                })
            })
            .collect::<Vec<_>>()
            .join(" ");
        return json!({
            "ok": false, "error": "busy", "message": format!("{title} is already in progress."),
            "action": name, "current_action": current, "unit": current_unit,
        });
    }
    let output = run(
        "systemctl",
        &["start", "--no-block", unit],
        Duration::from_secs(10),
    );
    if output.code != 0 {
        let detail = if output.stderr.is_empty() {
            &output.stdout
        } else {
            &output.stderr
        };
        return json!({
            "ok": false, "error": "action-rejected", "message": detail.trim(),
            "action": name, "unit": unit,
        });
    }
    json!({"ok": true, "accepted": true, "action": name, "unit": unit})
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let cmd = args.first().map(String::as_str).unwrap_or("snapshot");
    let payload = match cmd {
        "snapshot" if args.iter().any(|arg| arg == "--instant") => load_state(true, false),
        "snapshot" | "refresh" => {
            let explicit = cmd == "refresh";
            let full = explicit || args.iter().any(|arg| arg == "--refresh");
            let mut data = if full {
                let refresh = refresh_state();
                let mut data = load_state(false, true);
                decorate_state_health(&mut data, Some(refresh.clone()));
                if explicit {
                    data["refresh_ok"] = json!(refresh.is_ok());
                }
                if let Err(message) = refresh {
                    data["refresh_error"] = json!(message);
                }
                data
            } else {
                load_state(false, false)
            };
            // Keep the output path uniform for all command variants.
            if !data.is_object() {
                data = fallback_state("State unavailable");
            }
            data
        }
        "action" => args.get(1).map_or_else(
            || json!({"ok": false, "error": "missing-action", "message": "Action name required."}),
            |name| action(name),
        ),
        "ping" => json!({
            "ok": true, "service": "backup-recovery-control-center",
            "version": UI_CONTRACT, "time": now(),
        }),
        _ => json!({
            "ok": false, "error": "unknown-command", "message": format!("Unknown command: {cmd}"),
        }),
    };
    println!("{payload}");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_multiple_systemd_blocks_and_ignores_unknown_units() {
        let states = parse_unit_states(
            "Id=a.service\nActiveState=active\nExecMainStatus=0\n\nId=other.service\nActiveState=active\n\nId=b.service\nActiveState=inactive\nExecMainStatus=oops\n",
            &["a.service", "b.service"],
        );
        assert_eq!(states["a.service"]["active_state"], "active");
        assert_eq!(states["a.service"]["exec_main_status"], 0);
        assert_eq!(states["b.service"]["exec_main_status"], Value::Null);
        assert!(states.get("other.service").is_none());
    }

    #[test]
    fn contract_failures_are_explicit() {
        assert_eq!(
            contract_error(&json!({"schema_version": 2, "ui_contract": "1.6.0"})),
            None
        );
        assert!(
            contract_error(&json!({"schema_version": 3, "ui_contract": "1.6.0"}))
                .unwrap()
                .contains("schema")
        );
        assert!(
            contract_error(&json!({"schema_version": 2, "ui_contract": "other"}))
                .unwrap()
                .contains("UI contract")
        );
    }

    #[test]
    fn fallback_has_required_ui_contract() {
        let state = fallback_state("unavailable");
        assert_eq!(state["schema_version"], SCHEMA_VERSION);
        assert_eq!(state["ui_contract"], UI_CONTRACT);
        assert_eq!(state["overall"]["summary"], "unavailable");
        assert!(state["recovery"]["checks"].is_array());
    }
}
