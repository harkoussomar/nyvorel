//! One-shot Arch Remote controller. No Python interpreter is used at runtime.
use serde_json::{json, Map, Value};
use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::os::fd::AsRawFd;
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

mod activity;
mod audit;
mod cli;
mod domain;
mod export_logs;
mod exposure;
mod graphical;
mod hardening;
mod host;
mod integrity;
mod interfaces;
mod lan_share_security;
mod listeners;
mod live_derive;
mod lockdown_stop;
mod logs;
mod native_actions;
mod native_diagnostics;
mod native_misc;
mod native_pairing;
mod native_snapshot;
mod operation;
mod pair_support;
mod pairing_cancel;
mod pairing_create;
mod pairing_readiness;
mod phone_guide;
mod power;
mod process;
mod reference;
mod serve_funnel;
mod services;
mod ssh_evidence;
mod ssh_policy;
mod sshd_effective;
mod system_service_action;
mod tailscale;
mod user_service_action;
mod wayvnc_security;

const REVISION: &str = "2.4.1-rust-native";
const UI_CONTRACT: &str = "2.4.1";

fn now() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64()
}

fn home() -> PathBuf {
    env::var_os("HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .unwrap_or_else(|| PathBuf::from("/nonexistent"))
}

fn find_exe(name: &str) -> Option<PathBuf> {
    if name.contains('/') {
        let path = PathBuf::from(name);
        return path.is_file().then_some(path);
    }
    let path = env::var_os("PATH")?;
    env::split_paths(&path)
        .map(|directory| directory.join(name))
        .find(|candidate| {
            candidate.is_file()
                && fs::metadata(candidate).is_ok_and(|meta| meta.permissions().mode() & 0o111 != 0)
        })
}

fn runtime_dir() -> PathBuf {
    env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .unwrap_or_else(|| PathBuf::from(format!("/run/user/{}", unsafe { libc::getuid() })))
        .join("arch-remote")
}

fn error(state: &str, message: &str) -> Value {
    json!({"error": true, "ok": false, "state": state, "message": message})
}

fn read_json(path: &Path) -> Option<Value> {
    fs::read(path)
        .ok()
        .and_then(|data| serde_json::from_slice(&data).ok())
}

fn py_int(value: Option<&Value>) -> Result<i64, String> {
    match value {
        Some(Value::Number(n)) => Ok(n
            .as_i64()
            .or_else(|| n.as_f64().map(|v| v as i64))
            .unwrap_or(0)),
        Some(Value::String(s)) if !s.is_empty() => s.trim().parse().map_err(|_| {
            format!(
                "invalid literal for int() with base 10: '{}'",
                s.replace('\\', "\\\\").replace('\'', "\\'")
            )
        }),
        Some(Value::Bool(b)) => Ok(i64::from(*b)),
        _ => Ok(0),
    }
}

fn py_float(value: Option<&Value>) -> Result<f64, String> {
    match value {
        Some(Value::Number(n)) => Ok(n.as_f64().unwrap_or(0.0)),
        Some(Value::String(s)) if !s.is_empty() => s.trim().parse().map_err(|_| {
            format!(
                "could not convert string to float: '{}'",
                s.replace('\\', "\\\\").replace('\'', "\\'")
            )
        }),
        Some(Value::Bool(true)) => Ok(1.0),
        Some(Value::Bool(false)) => Ok(0.0),
        _ => Ok(0.0),
    }
}

fn py_truthy(value: Option<&Value>) -> bool {
    match value {
        None | Some(Value::Null | Value::Bool(false)) => false,
        Some(Value::Number(n)) => n.as_f64().unwrap_or(0.0) != 0.0,
        Some(Value::String(s)) => !s.is_empty(),
        Some(Value::Array(a)) => !a.is_empty(),
        Some(Value::Object(o)) => !o.is_empty(),
        _ => true,
    }
}

fn python_error(message: String) -> Value {
    json!({"error": true, "message": message})
}

fn py_string(value: Option<&Value>) -> String {
    match value {
        Some(Value::String(s)) => s.clone(),
        _ => String::new(),
    }
}

fn contract() -> Value {
    json!({"ok": true, "schema_version": 2, "ui_contract": UI_CONTRACT,
        "backend_revision": REVISION, "reference_schema_version": 1,
        "operation_contract": 1, "hardening_revision": "3.0-phase3-final",
        "deployment_integrity_contract": 1})
}

fn snapshot_cache() -> Value {
    let path = home().join(".local/state/nyvorel/arch-remote/runtime-state.json");
    let Some(Value::Object(mut state)) = read_json(&path) else {
        return error(
            "cache-missing",
            "No persisted Arch Remote state is available yet.",
        );
    };
    let schema = match py_int(state.get("schema_version")) {
        Ok(value) => value,
        Err(message) => return python_error(message),
    };
    if schema != 2 {
        return error(
            "cache-schema-mismatch",
            "Persisted state schema is incompatible.",
        );
    }
    if py_string(state.get("ui_contract")) != UI_CONTRACT {
        return error(
            "cache-contract-mismatch",
            "Persisted UI contract is incompatible.",
        );
    }
    let generated = match py_float(state.get("generated_at")) {
        Ok(value) => value,
        Err(message) => return python_error(message),
    };
    let cached_revision = py_string(state.get("backend_revision"));
    state.insert(
        "cache".into(),
        json!({"source": "persisted",
        "age_seconds": if generated != 0.0 { Some((now() - generated).max(0.0)) } else { None },
        "current_backend_revision": REVISION, "cached_backend_revision": cached_revision}),
    );
    Value::Object(state)
}

fn idle_operation() -> Map<String, Value> {
    json!({"id": "", "active": false, "status": "idle", "phase": "idle",
        "label": "", "kind": "", "args": [], "service": "", "action": "",
        "source": "", "pid": 0, "started_at": 0.0, "updated_at": 0.0,
        "finished_at": 0.0, "message": "", "result_state": "",
        "backend_revision": REVISION})
    .as_object()
    .unwrap()
    .clone()
}

struct Flock(File);
impl Flock {
    fn acquire(path: &Path) -> io::Result<Self> {
        Self::lock(path, libc::LOCK_EX)
    }

    fn try_acquire(path: &Path) -> io::Result<Self> {
        Self::lock(path, libc::LOCK_EX | libc::LOCK_NB)
    }

    fn lock(path: &Path, flags: libc::c_int) -> io::Result<Self> {
        let directory = path
            .parent()
            .ok_or_else(|| io::Error::other("lock has no parent"))?;
        fs::create_dir_all(directory)?;
        fs::set_permissions(directory, fs::Permissions::from_mode(0o700))?;
        let file = OpenOptions::new()
            .create(true)
            .read(true)
            .write(true)
            .truncate(false)
            .mode(0o600)
            .open(path)?;
        if unsafe { libc::flock(file.as_raw_fd(), flags) } != 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(Self(file))
    }
}
impl Drop for Flock {
    fn drop(&mut self) {
        unsafe {
            libc::flock(self.0.as_raw_fd(), libc::LOCK_UN);
        }
    }
}

fn pid_alive(pid: i64) -> bool {
    pid > 0 && pid <= i32::MAX as i64 && unsafe { libc::kill(pid as i32, 0) } == 0
}

fn atomic_json(path: &Path, value: &Value) -> io::Result<()> {
    let parent = path
        .parent()
        .ok_or_else(|| io::Error::other("operation has no parent"))?;
    fs::create_dir_all(parent)?;
    let mut temporary = None;
    for attempt in 0..16 {
        let candidate = parent.join(format!(
            "operation.json.{}.{}.tmp",
            std::process::id(),
            (now() * 1e9) as u64 + attempt
        ));
        match OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&candidate)
        {
            Ok(file) => {
                temporary = Some((candidate, file));
                break;
            }
            Err(err) if err.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(err) => return Err(err),
        }
    }
    let (candidate, mut file) =
        temporary.ok_or_else(|| io::Error::other("cannot create temporary operation file"))?;
    let result = (|| {
        serde_json::to_writer_pretty(&mut file, value)?;
        file.write_all(b"\n")?;
        file.sync_all()?;
        fs::rename(&candidate, path)?;
        File::open(parent)?.sync_all()
    })();
    if result.is_err() {
        let _ = fs::remove_file(candidate);
    }
    result
}

fn operation_status(requested_id: &str) -> Value {
    let directory = runtime_dir();
    let _lock = match Flock::acquire(&directory.join("operation-meta.lock")) {
        Ok(lock) => lock,
        Err(_) => {
            return json!({"error": true, "ok": false, "message": "Operation metadata is busy."})
        }
    };
    let path = directory.join("operation.json");
    let mut operation = idle_operation();
    if let Some(Value::Object(saved)) = read_json(&path) {
        operation.extend(saved);
    }
    if py_truthy(operation.get("active")) {
        let pid = match py_int(operation.get("pid")) {
            Ok(value) => value,
            Err(message) => return python_error(message),
        };
        if pid > 0 && !pid_alive(pid) {
            let time = now();
            operation.insert("active".into(), json!(false));
            operation.insert("status".into(), json!("failed"));
            operation.insert("phase".into(), json!("failed"));
            operation.insert("finished_at".into(), json!(time));
            operation.insert("updated_at".into(), json!(time));
            operation.insert(
                "message".into(),
                json!("The operation worker exited before publishing a final result."),
            );
            operation.insert("result_state".into(), json!("worker-exited"));
            operation.insert("backend_revision".into(), json!(REVISION));
            if atomic_json(&path, &Value::Object(operation.clone())).is_err() {
                return json!({"error": true, "ok": false, "message": "Could not persist operation status."});
            }
        }
    }
    if !requested_id.is_empty() && py_string(operation.get("id")) != requested_id {
        return json!({"error": true, "ok": false, "state": "operation-replaced",
            "message": "Requested operation is no longer the current operation.",
            "operation": operation});
    }
    json!({"ok": true, "operation": operation})
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.first().map(String::as_str) == Some("cli") {
        std::process::exit(cli::run(&args[1..]));
    }
    let result = match args.first().map(String::as_str) {
        Some("contract") => contract(),
        Some("snapshot-cache") => snapshot_cache(),
        Some("snapshot") => native_snapshot::run(args.get(1).map(String::as_str) == Some("--full")),
        Some("snapshot-native") => {
            native_snapshot::run(args.get(1).map(String::as_str) == Some("--full"))
        }
        Some("operation-status") => operation_status(args.get(1).map(String::as_str).unwrap_or("")),
        Some("operation-start") => operation::start_native(&args[1..]),
        Some("operation-start-native") => operation::start_native(&args[1..]),
        Some("operation-worker") => operation::worker_native(&args[1..]),
        Some("operation-worker-native") => operation::worker_native(&args[1..]),
        Some(
            "service"
            | "system-service"
            | "lockdown"
            | "verify-ssh-effective"
            | "service-native"
            | "system-service-native"
            | "lockdown-native"
            | "verify-ssh-effective-native",
        ) => {
            let kind = match args[0].as_str() {
                "service" | "service-native" => "service",
                "system-service" | "system-service-native" => "system-service",
                "lockdown" | "lockdown-native" => "lockdown",
                _ => "verify-ssh-effective",
            };
            native_actions::dispatch(kind, &args[1..])
        }
        Some("pairing-create" | "pairing-create-native") => native_pairing::create(),
        Some("pairing-cancel" | "pairing-cancel-native") => native_pairing::cancel(),
        Some("pairing-capability" | "pairing-capability-native") => native_pairing::capability(),
        Some("reference" | "reference-native") => native_misc::reference(),
        Some("record-event" | "record-event-native") => native_misc::record_event(&args[1..]),
        Some("copy" | "copy-native") => {
            native_misc::copy(args.get(1).map(String::as_str).unwrap_or(""))
        }
        Some("open-url" | "open-url-native") => {
            native_misc::open_url(args.get(1).map(String::as_str).unwrap_or(""))
        }
        Some("selftest" | "selftest-native") => native_diagnostics::selftest(),
        Some("validate" | "validate-native") => native_diagnostics::validate(),
        Some("operation-wait") => operation::wait(&args[1..]),
        Some("logs") => logs::run(&args[1..]),
        Some("export-logs") => export_logs::run(&args[1..]),
        Some("lockdown-stop") => lockdown_stop::run(),
        Some("services") => services::run(),
        Some("listeners") => listeners::run(
            args.get(1).map(String::as_str).unwrap_or(""),
            args.get(2).map(String::as_str).unwrap_or(""),
        ),
        Some("tailscale-status") => tailscale::run(),
        Some("interfaces") => interfaces::run(),
        Some("exposure") => exposure::run(),
        Some("serve-funnel") => serve_funnel::run(args.get(1).map(String::as_str).unwrap_or("")),
        Some("service-domain") => domain::run(),
        Some("graphical") => graphical::run(),
        Some("host") => host::run(),
        Some("host-graphical") => json!({"host": host::run(), "graphical": graphical::run()}),
        Some("power") => power::run(),
        Some("ssh-evidence") => ssh_evidence::run(args.get(1).map(String::as_str).unwrap_or("")),
        Some("sshd-effective") => sshd_effective::run(
            args.get(1).map(String::as_str).unwrap_or(""),
            args.get(2).map(String::as_str).unwrap_or(""),
            args.get(3).map(String::as_str).unwrap_or(""),
            args.get(4).map(String::as_str) == Some("1"),
        ),
        Some("hardening") if args.len() == 1 => {
            let base = home().join(".config/systemd/user");
            hardening::run(
                &base
                    .join("lan-share.service.d/20-arch-remote-hardening.conf")
                    .to_string_lossy(),
                &base
                    .join("wayvnc-remote.service.d/20-arch-remote-hardening.conf")
                    .to_string_lossy(),
            )
        }
        Some("hardening") => hardening::run(
            args.get(1).map(String::as_str).unwrap_or(""),
            args.get(2).map(String::as_str).unwrap_or(""),
        ),
        Some("integrity") if args.len() == 1 => integrity::run(
            &home()
                .join(".local/state/nyvorel/arch-remote/deployment.json")
                .to_string_lossy(),
        ),
        Some("integrity") => integrity::run(args.get(1).map(String::as_str).unwrap_or("")),
        Some("wayvnc-security") if args.len() == 1 => {
            let base = home().join(".config");
            wayvnc_security::run(
                &base.join("wayvnc/arch-remote.conf").to_string_lossy(),
                &base
                    .join("wayvnc/arch-remote-tls-key.pem")
                    .to_string_lossy(),
                &base
                    .join("wayvnc/arch-remote-tls-cert.pem")
                    .to_string_lossy(),
                &home().join(".local/bin/wayvnc-remote").to_string_lossy(),
                &base
                    .join("systemd/user/wayvnc-remote.service.d/99-arch-remote-security.conf")
                    .to_string_lossy(),
            )
        }
        Some("wayvnc-security") => wayvnc_security::run(
            args.get(1).map(String::as_str).unwrap_or(""),
            args.get(2).map(String::as_str).unwrap_or(""),
            args.get(3).map(String::as_str).unwrap_or(""),
            args.get(4).map(String::as_str).unwrap_or(""),
            args.get(5).map(String::as_str).unwrap_or(""),
        ),
        Some("lan-share-security") => {
            lan_share_security::run(args.get(1).map(String::as_str).unwrap_or(""))
        }
        Some("pair-support") => pair_support::run(args.get(1).map(String::as_str).unwrap_or("")),
        Some("security-audit") => audit::run(),
        Some("pairing-readiness") => pairing_readiness::run(),
        Some("phone-guide") => phone_guide::run(),
        Some("live-derive") => live_derive::run(),
        Some("reference-model") => reference::run(),
        Some("pairing-create-model") => pairing_create::run(),
        Some("pairing-cancel-model") => pairing_cancel::run(),
        Some("user-service-action") => user_service_action::run(),
        Some("system-service-action") => system_service_action::run(),
        Some("help" | "--help") => {
            json!({"ok": true, "commands": ["contract", "snapshot", "snapshot-cache", "operation-status", "operation-start", "operation-wait", "logs", "export-logs", "services", "listeners", "tailscale-status", "interfaces", "exposure", "serve-funnel", "service-domain", "graphical", "host", "host-graphical", "power", "ssh-evidence", "sshd-effective", "hardening", "integrity", "wayvnc-security", "lan-share-security", "pair-support", "security-audit", "pairing-readiness", "phone-guide", "live-derive", "reference", "pairing-create", "pairing-cancel", "user-service-action", "system-service-action"]})
        }
        _ => json!({"error": true, "message": "unsupported Rust fast-path command"}),
    };
    println!("{result}");
}
