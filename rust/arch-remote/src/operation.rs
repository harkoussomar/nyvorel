//! One-shot operation scheduling. The child exits after the action and status write.
use serde_json::{json, Map, Value};
use std::env;
use std::fs::File;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

use crate::{
    atomic_json, idle_operation, now, operation_status, pid_alive, read_json, runtime_dir, Flock,
    REVISION,
};

fn operation_file() -> PathBuf {
    runtime_dir().join("operation.json")
}

fn read_operation(path: &Path) -> Map<String, Value> {
    let mut operation = idle_operation();
    if let Some(Value::Object(saved)) = read_json(path) {
        operation.extend(saved);
    }
    operation
}

fn write_operation(path: &Path, operation: &mut Map<String, Value>) -> Result<(), ()> {
    operation.insert("backend_revision".into(), json!(REVISION));
    atomic_json(path, &Value::Object(operation.clone())).map_err(|_| ())
}

fn random_id() -> Result<String, ()> {
    let mut bytes = [0_u8; 16];
    File::open("/dev/urandom")
        .and_then(|mut file| file.read_exact(&mut bytes))
        .map_err(|_| ())?;
    Ok(bytes.iter().map(|byte| format!("{byte:02x}")).collect())
}

fn spec(kind: &str, args: &[String]) -> Option<(String, String, String)> {
    match (kind, args) {
        ("service", [name, action])
            if matches!(name.as_str(), "lan-share" | "wayvnc-remote")
                && matches!(action.as_str(), "start" | "stop" | "restart") =>
        {
            let label = if name == "lan-share" {
                "Private Share"
            } else {
                "Remote Desktop"
            };
            let verb = match action.as_str() {
                "start" => "Starting",
                "stop" => "Stopping",
                _ => "Restarting",
            };
            Some((format!("{verb} {label}"), name.clone(), action.clone()))
        }
        ("system-service", [name, action])
            if name == "tailscaled" && matches!(action.as_str(), "start" | "restart") =>
        {
            Some((
                if action == "start" {
                    "Starting Tailscale"
                } else {
                    "Restarting Tailscale"
                }
                .into(),
                name.clone(),
                action.clone(),
            ))
        }
        ("lockdown", []) => Some((
            "Locking interactive sharing".into(),
            String::new(),
            "lockdown".into(),
        )),
        ("verify-ssh-effective", []) => Some((
            "Verifying effective SSH policy".into(),
            "sshd".into(),
            "verify".into(),
        )),
        _ => None,
    }
}

fn error(state: &str, message: &str) -> Value {
    json!({"error": true, "ok": false, "state": state, "message": message})
}

pub fn start_native(args: &[String]) -> Value {
    start_with_worker(args)
}

fn start_with_worker(args: &[String]) -> Value {
    let Some((kind, rest)) = args.split_first() else {
        return error("invalid", "Unsupported persistent operation.");
    };
    let Some((label, service, action)) = spec(kind, rest) else {
        return error("invalid", "Unsupported persistent operation.");
    };
    let directory = runtime_dir();
    let Ok(_meta_lock) = Flock::acquire(&directory.join("operation-meta.lock")) else {
        return error("busy", "Operation metadata is busy.");
    };
    let path = operation_file();
    let mut current = read_operation(&path);
    if current.get("active").and_then(Value::as_bool) == Some(true) {
        let pid = current.get("pid").and_then(Value::as_i64).unwrap_or(0);
        if pid <= 0 || pid_alive(pid) {
            let previous = current
                .get("label")
                .and_then(Value::as_str)
                .unwrap_or("another Arch Remote action");
            return json!({"error": true, "ok": false, "state": "busy", "message": format!("Busy: {previous} is already in progress."), "operation": current});
        }
        let time = now();
        current.insert("active".into(), json!(false));
        current.insert("status".into(), json!("failed"));
        current.insert("phase".into(), json!("failed"));
        current.insert("finished_at".into(), json!(time));
        current.insert("updated_at".into(), json!(time));
        current.insert(
            "message".into(),
            json!("Previous operation worker disappeared."),
        );
        current.insert("result_state".into(), json!("worker-exited"));
        if write_operation(&path, &mut current).is_err() {
            return error("failed", "Could not persist previous operation status.");
        }
    }
    let Ok(_action_available) = Flock::try_acquire(&directory.join("action.lock")) else {
        return error(
            "busy",
            "Busy: another controller process owns the Arch Remote action lock.",
        );
    };
    drop(_action_available);
    let Ok(id) = random_id() else {
        return error("failed", "Could not create operation ID.");
    };
    let time = now();
    let mut operation = idle_operation();
    operation.insert("id".into(), json!(id));
    operation.insert("active".into(), json!(true));
    operation.insert("status".into(), json!("queued"));
    operation.insert("phase".into(), json!("queued"));
    operation.insert("label".into(), json!(label));
    operation.insert("kind".into(), json!(kind));
    operation.insert("args".into(), json!(rest));
    operation.insert("service".into(), json!(service));
    operation.insert("action".into(), json!(action));
    operation.insert(
        "source".into(),
        json!(
            if env::var("ARCH_REMOTE_CLI").ok().as_deref() == Some("1") {
                "cli"
            } else {
                "ui"
            }
        ),
    );
    operation.insert("started_at".into(), json!(time));
    operation.insert("updated_at".into(), json!(time));
    if write_operation(&path, &mut operation).is_err() {
        return error("failed", "Could not persist queued operation.");
    }
    let Ok(executable) = env::current_exe() else {
        return fail_start(
            &path,
            operation,
            "Could not locate operation worker binary.",
        );
    };
    let child = Command::new(executable)
        .arg("operation-worker-native")
        .arg(&id)
        .arg(kind)
        .args(rest)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
    let Ok(child) = child else {
        return fail_start(&path, operation, "Could not launch operation worker.");
    };
    operation.insert("pid".into(), json!(child.id()));
    operation.insert("updated_at".into(), json!(now()));
    if write_operation(&path, &mut operation).is_err() {
        return error(
            "failed",
            "Worker launched, but operation status could not be persisted.",
        );
    }
    json!({"ok": true, "accepted": true, "message": label, "operation": operation})
}

fn fail_start(path: &Path, mut operation: Map<String, Value>, message: &str) -> Value {
    operation.insert("active".into(), json!(false));
    operation.insert("status".into(), json!("failed"));
    operation.insert("phase".into(), json!("failed"));
    operation.insert("finished_at".into(), json!(now()));
    operation.insert("updated_at".into(), json!(now()));
    operation.insert("message".into(), json!(message));
    operation.insert("result_state".into(), json!("worker-launch-failed"));
    let _ = write_operation(path, &mut operation);
    error("failed", message)
}

pub fn worker_native(args: &[String]) -> Value {
    worker_mode(args)
}

fn worker_mode(args: &[String]) -> Value {
    let Some((id, command)) = args.split_first() else {
        return error("invalid", "Missing operation ID.");
    };
    let Some((kind, rest)) = command.split_first() else {
        return error("invalid", "Missing operation kind.");
    };
    if spec(kind, rest).is_none() {
        return error("invalid", "Unsupported operation worker command.");
    }
    let directory = runtime_dir();
    let path = operation_file();
    {
        let Ok(_lock) = Flock::acquire(&directory.join("operation-meta.lock")) else {
            return error("busy", "Operation metadata is busy.");
        };
        let mut current = read_operation(&path);
        if current.get("id").and_then(Value::as_str) != Some(id)
            || current.get("kind").and_then(Value::as_str) != Some(kind)
            || current.get("args") != Some(&json!(rest))
            || current.get("active").and_then(Value::as_bool) != Some(true)
            || current.get("status").and_then(Value::as_str) != Some("queued")
            || current.get("pid").and_then(Value::as_u64) != Some(std::process::id() as u64)
        {
            return error(
                "operation-replaced",
                "Operation worker no longer matches queued action.",
            );
        }
        current.insert("status".into(), json!("running"));
        current.insert("phase".into(), json!("running"));
        current.insert("pid".into(), json!(std::process::id()));
        current.insert("updated_at".into(), json!(now()));
        if write_operation(&path, &mut current).is_err() {
            return error("failed", "Could not publish running status.");
        }
    }
    let result = crate::native_actions::dispatch(kind, rest);
    let failed = result.get("error").and_then(Value::as_bool) == Some(true)
        || result.get("ok").and_then(Value::as_bool) != Some(true);
    let message = result
        .get("message")
        .and_then(Value::as_str)
        .unwrap_or(if failed {
            "Operation failed"
        } else {
            "Operation complete"
        });
    let state = result
        .get("state")
        .and_then(Value::as_str)
        .unwrap_or(if failed { "failed" } else { "complete" });
    let Ok(_lock) = Flock::acquire(&directory.join("operation-meta.lock")) else {
        return error("busy", "Could not publish operation result.");
    };
    let mut current = read_operation(&path);
    if current.get("id").and_then(Value::as_str) != Some(id) {
        return error(
            "operation-replaced",
            "Operation was replaced before completion.",
        );
    }
    current.insert("active".into(), json!(false));
    current.insert(
        "status".into(),
        json!(if failed { "failed" } else { "succeeded" }),
    );
    current.insert(
        "phase".into(),
        json!(if failed { "failed" } else { "complete" }),
    );
    current.insert("updated_at".into(), json!(now()));
    current.insert("finished_at".into(), json!(now()));
    current.insert(
        "message".into(),
        json!(message.chars().take(800).collect::<String>()),
    );
    current.insert(
        "result_state".into(),
        json!(state.chars().take(120).collect::<String>()),
    );
    if write_operation(&path, &mut current).is_err() {
        return error("failed", "Could not persist operation result.");
    }
    json!({"ok": !failed, "operation": current})
}

pub fn wait(args: &[String]) -> Value {
    let Some(id) = args.first() else {
        return error("invalid", "Missing operation ID.");
    };
    let timeout = args
        .get(1)
        .and_then(|s| s.parse::<f64>().ok())
        .unwrap_or(45.0)
        .clamp(0.5, 120.0);
    let deadline = Instant::now() + Duration::from_secs_f64(timeout);
    loop {
        let latest = operation_status(id);
        if latest.get("error").and_then(Value::as_bool) == Some(true) {
            return latest;
        }
        if latest.pointer("/operation/active").and_then(Value::as_bool) != Some(true) {
            return latest;
        }
        if Instant::now() >= deadline {
            return json!({"error": true, "ok": false, "state": "timeout", "message": "Timed out waiting for operation completion.", "operation": latest.get("operation")});
        }
        thread::sleep(Duration::from_millis(200));
    }
}
