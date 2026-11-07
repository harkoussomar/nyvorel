use crate::collector;
use crate::root_common::{
    atomic_bytes, atomic_json, boolish, chown_root_group, hostname, nonempty, now, number,
    read_json, run, run_env, string, user_ids, Lock, Output, Paths, BACKEND_REVISION,
};
use chrono::DateTime;
use regex::Regex;
use serde_json::{json, Value};
use std::collections::HashSet;
use std::fs;
use std::io::Read;
use std::path::{Component, Path};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

const LABELS: &[(&str, &str)] = &[
    ("backup", "Backup"),
    ("timeshift", "Timeshift restore point"),
    ("restic-check", "Repository verification"),
    ("restore-test", "Restore verification"),
    ("smart-short", "SMART short test"),
    ("smart-long", "SMART extended test"),
    ("mount", "Backup HDD mount"),
    ("eject", "Backup HDD safe eject"),
    ("refresh-manifests", "Recovery manifest refresh"),
];

fn label(name: &str) -> String {
    LABELS
        .iter()
        .find(|(key, _)| *key == name)
        .map_or_else(|| name.replace('-', " "), |(_, value)| (*value).into())
}

fn duration(seconds: i64) -> String {
    let value = seconds.max(0);
    if value >= 3600 {
        format!("{}h {:02}m", value / 3600, value % 3600 / 60)
    } else if value >= 60 {
        format!("{}m {:02}s", value / 60, value % 60)
    } else {
        format!("{value}s")
    }
}

fn notification_enabled(cfg: &Value, event: &str, action: &str) -> bool {
    let policy = &cfg["notifications"];
    if policy["enabled"] == false {
        return false;
    }
    let default: &[&str] = match event {
        "start" => &[
            "backup",
            "timeshift",
            "restic-check",
            "restore-test",
            "smart-long",
        ],
        "success" => &[
            "backup",
            "timeshift",
            "restic-check",
            "restore-test",
            "refresh-manifests",
        ],
        "failure" => &["*"],
        _ => &[],
    };
    let allowed: Vec<String> = match &policy[event] {
        Value::Null => default.iter().map(|item| (*item).into()).collect(),
        Value::Bool(true) => vec!["*".into()],
        Value::Array(items) => items.iter().map(string).collect(),
        _ => Vec::new(),
    };
    allowed.iter().any(|item| item == "*" || item == action)
}

fn notify(cfg: &Value, event: &str, action: &str, title: &str, body: &str, urgency: &str) {
    if !notification_enabled(cfg, event, action) {
        return;
    }
    let user = string(&cfg["user"]).trim().to_owned();
    let Ok((uid, _, _)) = user_ids(&user) else {
        return;
    };
    if !Path::new("/usr/bin/notify-send").is_file()
        || !Path::new("/usr/bin/runuser").is_file()
        || !Path::new(&format!("/run/user/{uid}/bus")).exists()
    {
        return;
    }
    let title: String = title.trim().chars().take(160).collect();
    let body: String = body
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .chars()
        .take(900)
        .collect();
    let runtime = format!("XDG_RUNTIME_DIR=/run/user/{uid}");
    let bus = format!("DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{uid}/bus");
    let urgency = format!("--urgency={urgency}");
    let _ = run(
        "/usr/bin/runuser",
        &[
            "-u",
            &user,
            "--",
            "/usr/bin/env",
            &runtime,
            &bus,
            "/usr/bin/notify-send",
            "--app-name=Backup & Recovery",
            "--icon=drive-harddisk-symbolic",
            &urgency,
            "--expire-time=7000",
            &title,
            &body,
        ],
        4,
    );
}

fn record(
    paths: &Paths,
    kind: &str,
    title: &str,
    detail: &str,
    severity: &str,
) -> Result<(), String> {
    let _lock = Lock::acquire(&paths.at("/run/backup-recovery/activity.lock"), false)?;
    let path = paths.state("activity.json");
    let data = read_json(&path, json!([]));
    let mut rows = data.as_array().cloned().unwrap_or_default();
    rows.push(json!({"time": now(), "kind": kind, "title": title, "detail": detail, "severity": severity}));
    if rows.len() > 120 {
        rows.drain(..rows.len() - 120);
    }
    atomic_json(&path, &json!(rows), 0o640)
}

struct Context<'a> {
    paths: &'a Paths,
    config: Value,
    name: &'a str,
    started: i64,
    success_message: Option<String>,
}

impl Context<'_> {
    fn publish(
        &self,
        state: &str,
        phase: &str,
        progress: Value,
        message: &str,
        finished: Option<i64>,
    ) -> Result<(), String> {
        let payload = json!({
            "schema_version": 1, "action": self.name, "state": state, "phase": phase,
            "started_at": self.started, "updated_at": now(), "finished_at": finished,
            "message": message, "progress": progress,
        });
        let path = self.paths.state("action-state.json");
        atomic_json(&path, &payload, 0o640)?;
        if self.paths.real_system() {
            let user = string(&self.config["user"]);
            if let Ok((_, gid, _)) = user_ids(user.trim()) {
                chown_root_group(&path, gid, 0o640)?;
            }
        }
        Ok(())
    }

    fn phase(&self, label: &str) -> Result<(), String> {
        self.publish("running", label, json!({}), "", None)
    }

    fn progress(&self, label: &str, progress: Value) -> Result<(), String> {
        self.publish("running", label, progress, "", None)
    }

    fn marker(&self, name: &str, payload: Value) -> Result<(), String> {
        let path = self.paths.state(name);
        atomic_json(&path, &payload, 0o640)?;
        if self.paths.real_system() {
            let user = string(&self.config["user"]);
            if let Ok((_, gid, _)) = user_ids(user.trim()) {
                chown_root_group(&path, gid, 0o640)?;
            }
        }
        Ok(())
    }

    fn record(&self, kind: &str, title: &str, detail: &str, severity: &str) -> Result<(), String> {
        record(self.paths, kind, title, detail, severity)
    }

    fn restic_args(&self) -> Vec<String> {
        vec![
            "-r".into(),
            string(&self.config["restic_repo"]),
            "--password-file".into(),
            string(&self.config["restic_password_file"]),
            "--cache-dir".into(),
            string(&self.config["restic_cache_dir"]),
        ]
    }

    fn restic(&self, tail: &[&str], timeout: u64) -> Output {
        let base = self.restic_args();
        let args: Vec<&str> = base
            .iter()
            .map(String::as_str)
            .chain(tail.iter().copied())
            .collect();
        run("restic", &args, timeout)
    }

    fn repository_id(&self) -> Result<String, String> {
        let output = self.restic(&["cat", "config"], 60);
        if output.code != 0 {
            return Err(if output.detail().is_empty() {
                "Unable to read Restic repository identity.".into()
            } else {
                output.detail()
            });
        }
        let data: Value = serde_json::from_slice(&output.stdout)
            .map_err(|error| format!("Invalid Restic repository config JSON: {error}"))?;
        let id = string(&data["id"]).trim().to_owned();
        if id.is_empty() {
            Err("Restic repository did not expose a stable repository ID.".into())
        } else {
            Ok(id)
        }
    }

    fn expected_host(&self) -> String {
        nonempty(&self.config["restic_expected_hostname"], &hostname())
            .trim()
            .into()
    }

    fn matching_snapshots(&self) -> Result<Vec<Value>, String> {
        let output = self.restic(&["snapshots", "--json"], 90);
        if output.code != 0 {
            return Err(if output.detail().is_empty() {
                "Unable to query Restic snapshots.".into()
            } else {
                output.detail()
            });
        }
        let data: Value = serde_json::from_slice(&output.stdout)
            .map_err(|error| format!("Invalid Restic snapshot JSON: {error}"))?;
        let expected = self.expected_host();
        let required_tags: HashSet<String> = strings(&self.config["restic_required_tags"])
            .into_iter()
            .collect();
        let required_paths: HashSet<String> = strings(&self.config["restic_required_paths"])
            .into_iter()
            .collect();
        let mut rows: Vec<Value> = data
            .as_array()
            .ok_or("Restic snapshots response is not an array")?
            .iter()
            .filter(|row| row.is_object())
            .filter(|row| {
                (expected.is_empty() || string(&row["hostname"]) == expected)
                    && required_tags.is_subset(&strings(&row["tags"]).into_iter().collect())
                    && required_paths.is_subset(&strings(&row["paths"]).into_iter().collect())
            })
            .cloned()
            .collect();
        rows.sort_by(|a, b| string(&b["time"]).cmp(&string(&a["time"])));
        Ok(rows)
    }

    fn latest_snapshot(&self) -> Result<Option<Value>, String> {
        Ok(self.matching_snapshots()?.into_iter().next())
    }
}

fn strings(value: &Value) -> Vec<String> {
    value.as_array().map_or_else(Vec::new, |items| {
        items
            .iter()
            .map(string)
            .filter(|item| !item.is_empty())
            .collect()
    })
}

fn verify_mount(config: &Value) -> Result<String, String> {
    let mountpoint = string(&config["mountpoint"]).trim().to_owned();
    let expected = string(&config["backup_uuid"]).trim().to_owned();
    if mountpoint.is_empty() {
        return Err("Backup mountpoint is not configured.".into());
    }
    if expected.is_empty() {
        return Err("Backup filesystem UUID is not configured.".into());
    }
    if run("mountpoint", &["-q", &mountpoint], 5).code != 0 {
        return Err(format!("Backup disk is not mounted at {mountpoint}."));
    }
    let output = run("findmnt", &["-rn", "-o", "UUID", &mountpoint], 5);
    let actual = if output.code == 0 {
        output.out().trim().to_owned()
    } else {
        String::new()
    };
    if actual.is_empty() {
        return Err(format!("Filesystem mounted at {mountpoint}, but its UUID could not be verified. Backup/recovery actions were blocked."));
    }
    if actual != expected {
        return Err(format!(
            "Wrong filesystem mounted at {mountpoint}: expected UUID {expected}, found {actual}."
        ));
    }
    Ok(mountpoint)
}

fn resolve_disk(uuid: &str, paths: &Paths) -> Result<String, String> {
    let link = paths.at("/dev/disk/by-uuid").join(uuid);
    if !link.exists() {
        return Err("Backup HDD is not connected.".into());
    }
    let part = fs::canonicalize(&link).map_err(|error| error.to_string())?;
    let part = part.to_string_lossy();
    let parent = run("lsblk", &["-ndo", "PKNAME", &part], 5)
        .out()
        .trim()
        .to_owned();
    if parent.is_empty() {
        Err(format!("Unable to resolve physical disk for {part}."))
    } else {
        Ok(format!("/dev/{parent}"))
    }
}

fn progress_from_text(text: &str) -> Value {
    let mut latest = Value::Null;
    for raw in text.lines() {
        let Some(start) = raw.find('{') else { continue };
        let Ok(item) = serde_json::from_str::<Value>(&raw[start..]) else {
            continue;
        };
        if item["message_type"] == "status" {
            latest = item;
        }
    }
    if latest.is_null() {
        return json!({});
    }
    let mut result = json!({});
    if let Some(value) = latest["percent_done"].as_f64() {
        result["percent"] = json!((value * 100.0).clamp(0.0, 100.0));
    }
    for (source, target) in [
        ("files_done", "files_done"),
        ("total_files", "files_total"),
        ("bytes_done", "bytes_done"),
        ("total_bytes", "bytes_total"),
        ("seconds_remaining", "eta_seconds"),
    ] {
        if latest[source].is_number() {
            result[target] = latest[source].clone();
        }
    }
    result
}

fn read_progress(unit: &str, since: i64) -> Value {
    let since = format!("@{}", (since - 2).max(0));
    let output = run(
        "journalctl",
        &[
            "-u",
            unit,
            "--since",
            &since,
            "--no-pager",
            "-o",
            "cat",
            "-n",
            "160",
        ],
        8,
    );
    if output.code == 0 {
        progress_from_text(&output.out())
    } else {
        json!({})
    }
}

fn systemd_job(ctx: &Context<'_>, unit: &str, timeout: u64) -> Result<(), String> {
    let mut child = Command::new("systemctl")
        .args(["start", unit])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| error.to_string())?;
    let mut stdout = child
        .stdout
        .take()
        .ok_or("systemctl stdout pipe unavailable")?;
    let mut stderr = child
        .stderr
        .take()
        .ok_or("systemctl stderr pipe unavailable")?;
    let stdout_reader = thread::spawn(move || {
        let mut bytes = Vec::new();
        let _ = (&mut stdout).take(1_048_576).read_to_end(&mut bytes);
        bytes
    });
    let stderr_reader = thread::spawn(move || {
        let mut bytes = Vec::new();
        let _ = (&mut stderr).take(1_048_576).read_to_end(&mut bytes);
        bytes
    });
    let deadline = Instant::now() + Duration::from_secs(timeout);
    let mut progress = json!({});
    loop {
        match child.try_wait().map_err(|error| error.to_string())? {
            Some(status) => {
                let out = stdout_reader.join().unwrap_or_default();
                let err = stderr_reader.join().unwrap_or_default();
                if !status.success() {
                    let detail = String::from_utf8_lossy(if err.is_empty() { &out } else { &err })
                        .trim()
                        .to_owned();
                    return Err(if detail.is_empty() {
                        "Restic backup service failed.".into()
                    } else {
                        detail
                    });
                }
                break;
            }
            None if Instant::now() < deadline => {
                let updated = read_progress(unit, ctx.started);
                if boolish(&updated) {
                    progress = updated;
                    ctx.progress("Backing up protected files", progress.clone())?;
                } else {
                    ctx.progress("Restic backup running", progress.clone())?;
                }
                thread::sleep(Duration::from_secs(2));
            }
            None => {
                let _ = child.kill();
                let _ = child.wait();
                let _ = stdout_reader.join();
                let _ = stderr_reader.join();
                return Err(format!("{unit} did not finish within {timeout}s"));
            }
        }
    }
    loop {
        let state = run("systemctl", &["is-active", unit], 5)
            .out()
            .trim()
            .to_owned();
        if !matches!(state.as_str(), "active" | "activating" | "reloading") {
            break;
        }
        if Instant::now() >= deadline {
            return Err(format!("{unit} did not finish within {timeout}s"));
        }
        let updated = read_progress(unit, ctx.started);
        if boolish(&updated) {
            progress = updated;
            ctx.progress("Backing up protected files", progress.clone())?;
        } else {
            ctx.progress("Restic backup running", progress.clone())?;
        }
        thread::sleep(Duration::from_secs(2));
    }
    let show = run(
        "systemctl",
        &[
            "show",
            unit,
            "--property=Result,ExecMainStatus",
            "--no-pager",
        ],
        8,
    );
    let mut result = String::new();
    let mut status = 0;
    for line in show.out().lines() {
        if let Some((key, value)) = line.split_once('=') {
            match key {
                "Result" => result = value.trim().into(),
                "ExecMainStatus" => status = value.trim().parse().unwrap_or(0),
                _ => {}
            }
        }
    }
    if !result.is_empty() && result != "success" {
        return Err(format!("{unit} finished with result {result}"));
    }
    if status != 0 {
        return Err(format!("{unit} exited with status {status}"));
    }
    Ok(())
}

fn snapshot_timestamp(value: &str) -> i64 {
    DateTime::parse_from_rfc3339(value).map_or(0, |date| date.timestamp())
}

fn backup_allows_unchanged(cfg: &Value) -> bool {
    if let Some(explicit) = cfg["restic_allow_unchanged_backup"].as_bool() {
        return explicit;
    }
    let output = run(
        "systemctl",
        &["cat", "restic-system-backup.service", "--no-pager"],
        10,
    );
    let mut definition = output.out();
    let token = Regex::new(r#"(?:"([^"]+)"|'([^']+)'|(\S+))"#).unwrap();
    for line in definition.clone().lines() {
        let Some(command) = line.trim().strip_prefix("ExecStart=") else {
            continue;
        };
        for capture in token.captures_iter(command.trim_start_matches('-').trim()) {
            let value = (1..=3)
                .find_map(|index| capture.get(index))
                .map_or("", |item| item.as_str());
            if !value.starts_with('/') {
                continue;
            }
            let Ok(resolved) = fs::canonicalize(value) else {
                continue;
            };
            let allowed = ["/usr/local/", "/opt/", "/usr/bin/", "/usr/lib/", "/home/"];
            if !allowed
                .iter()
                .any(|prefix| resolved.to_string_lossy().starts_with(prefix))
            {
                continue;
            }
            if !resolved.is_file()
                || fs::metadata(&resolved).map_or(true, |meta| meta.len() > 2_000_000)
            {
                continue;
            }
            if let Ok(text) = fs::read_to_string(resolved) {
                definition.push('\n');
                definition.push_str(&text);
            }
        }
    }
    definition.contains("--skip-if-unchanged")
}

fn backup(ctx: &mut Context<'_>) -> Result<(), String> {
    ctx.phase("Verifying backup disk")?;
    verify_mount(&ctx.config)?;
    if !Path::new(&string(&ctx.config["restic_repo"])).is_dir() {
        return Err("Restic repository directory is missing on the mounted backup disk.".into());
    }
    if !Path::new(&string(&ctx.config["restic_password_file"])).is_file() {
        return Err("Restic password file is missing.".into());
    }
    ctx.phase("Reading repository identity")?;
    let before_repo = ctx.repository_id()?;
    let before = ctx.latest_snapshot()?;
    let before_id = before
        .as_ref()
        .map_or_else(String::new, |row| string(&row["id"]));
    ctx.phase("Starting Restic backup")?;
    systemd_job(ctx, "restic-system-backup.service", 7200)?;
    ctx.phase("Verifying resulting snapshot")?;
    let after_repo = ctx.repository_id()?;
    if after_repo != before_repo {
        return Err("Restic repository identity changed while the backup was running.".into());
    }
    let after = ctx.latest_snapshot()?.ok_or_else(|| {
        format!(
            "Backup service succeeded, but no snapshot matched the expected host/scope ({}).",
            ctx.expected_host()
        )
    })?;
    let after_id = string(&after["id"]);
    let short = nonempty(
        &after["short_id"],
        &after_id.chars().take(8).collect::<String>(),
    );
    let timestamp = string(&after["time"]);
    let mut result = "new-snapshot";
    if !before_id.is_empty() && before_id == after_id {
        if !backup_allows_unchanged(&ctx.config) {
            ctx.marker("backup-proof.json", json!({
                "ok": false, "time": now(),
                "detail": "Backup service exited successfully but no new matching snapshot was created.",
                "backup_uuid": string(&ctx.config["backup_uuid"]), "repository_id": after_repo,
                "snapshot_id": after_id, "snapshot_time": timestamp,
                "hostname": string(&after["hostname"]), "backend_revision": BACKEND_REVISION,
            }))?;
            return Err(
                "Backup service succeeded, but no new expected Restic snapshot was verified."
                    .into(),
            );
        }
        result = "unchanged-skip";
    } else {
        let ts = snapshot_timestamp(&timestamp);
        if ts != 0 && ts < ctx.started - 5 {
            return Err("The newest matching Restic snapshot predates this backup action.".into());
        }
    }
    let detail = if result == "new-snapshot" {
        format!("New matching Restic snapshot {short} verified.")
    } else {
        format!("No-change backup verified against existing snapshot {short}; service is configured to skip unchanged snapshots.")
    };
    ctx.marker(
        "backup-proof.json",
        json!({
            "ok": true, "time": now(), "detail": detail, "result": result,
            "backup_uuid": string(&ctx.config["backup_uuid"]), "repository_id": after_repo,
            "snapshot_id": after_id, "snapshot_time": timestamp,
            "hostname": string(&after["hostname"]), "tags": after["tags"], "paths": after["paths"],
            "backend_revision": BACKEND_REVISION,
        }),
    )?;
    ctx.success_message = Some(detail.clone());
    ctx.record(
        "backup",
        "Restic backup verified",
        &format!("{detail} Repository identity and snapshot scope matched."),
        "success",
    )
}

fn snapshot_names(root: &Path) -> HashSet<String> {
    fs::read_dir(root)
        .ok()
        .into_iter()
        .flatten()
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| path.is_dir())
        .filter_map(|path| {
            path.file_name()
                .map(|name| name.to_string_lossy().into_owned())
        })
        .collect()
}

fn timeshift(ctx: &Context<'_>) -> Result<(), String> {
    ctx.phase("Verifying backup disk")?;
    let mountpoint = verify_mount(&ctx.config)?;
    let root = Path::new(&mountpoint).join("timeshift/snapshots");
    let before = snapshot_names(&root);
    ctx.phase("Creating Timeshift restore point")?;
    let output = run(
        "timeshift",
        &[
            "--create",
            "--comments",
            "Backup & Recovery Center restore point",
            "--tags",
            "O",
        ],
        7200,
    );
    if output.code != 0 {
        let detail = output.detail();
        return Err(if detail.is_empty() {
            "Timeshift snapshot failed.".into()
        } else {
            detail
                .chars()
                .rev()
                .take(1200)
                .collect::<String>()
                .chars()
                .rev()
                .collect()
        });
    }
    let mut created: Vec<String> = snapshot_names(&root).difference(&before).cloned().collect();
    created.sort();
    let detail = created.last().map_or_else(
        || "Timeshift reported success; snapshot inventory will be refreshed.".into(),
        |name| format!("Created {name}."),
    );
    ctx.record("timeshift", "Restore point created", &detail, "success")
}

fn restic_check(ctx: &mut Context<'_>) -> Result<(), String> {
    ctx.phase("Verifying backup disk")?;
    verify_mount(&ctx.config)?;
    let repo = ctx.repository_id()?;
    let snapshot = ctx.latest_snapshot()?;
    let snapshot_id = snapshot
        .as_ref()
        .map_or_else(String::new, |row| string(&row["id"]));
    let configured_subsets = number(&ctx.config["restic_data_check_subsets"]);
    let total = if configured_subsets <= 0 {
        4
    } else {
        configured_subsets
    };
    let previous = read_json(&ctx.paths.state("restic-data-check.json"), json!({}));
    let mut subset = number(&previous["next_subset"]).max(1);
    if string(&previous["repository_id"]) != repo
        || string(&previous["backup_uuid"]) != string(&ctx.config["backup_uuid"])
        || (if previous["total_subsets"].is_null() {
            total
        } else {
            number(&previous["total_subsets"])
        }) != total
    {
        subset = 1;
    }
    subset = subset.clamp(1, total);
    let help = ctx.restic(&["check", "--help"], 30);
    let supported = format!("{}{}", help.out(), help.err()).contains("--read-data-subset");
    let mode: String;
    let output = if supported {
        ctx.phase(&format!(
            "Checking structure + data subset {subset}/{total}"
        ))?;
        mode = format!("structural+data-subset-{subset}/{total}");
        ctx.restic(
            &["check", &format!("--read-data-subset={subset}/{total}")],
            7200,
        )
    } else {
        ctx.phase("Checking Restic repository structure")?;
        mode = "structural".into();
        ctx.restic(&["check"], 7200)
    };
    let detail = output.detail();
    let tail: String = detail
        .chars()
        .rev()
        .take(1200)
        .collect::<String>()
        .chars()
        .rev()
        .collect();
    if output.code != 0 {
        let marker = json!({
            "ok": false, "time": now(), "detail": if tail.is_empty() { "Restic repository verification failed." } else { &tail },
            "verification_mode": mode, "backup_uuid": string(&ctx.config["backup_uuid"]),
            "repository_id": repo, "snapshot_id": snapshot_id, "backend_revision": BACKEND_REVISION,
        });
        ctx.marker("restic-check-ok.json", marker.clone())?;
        if supported {
            ctx.marker(
                "restic-data-check.json",
                json!({
                    "known": true, "ok": false, "time": marker["time"],
                    "detail": marker["detail"], "subset": subset, "total_subsets": total,
                    "next_subset": subset, "cycle_completed": false,
                    "backup_uuid": marker["backup_uuid"], "repository_id": repo,
                    "snapshot_id": snapshot_id, "backend_revision": BACKEND_REVISION,
                }),
            )?;
        }
        return Err(if detail.is_empty() {
            "Restic repository verification failed.".into()
        } else {
            detail
        });
    }
    if supported {
        ctx.marker("restic-data-check.json", json!({
            "known": true, "ok": true, "time": now(),
            "detail": if tail.is_empty() { format!("Repository data subset {subset}/{total} verified.") } else { tail.clone() },
            "subset": subset, "total_subsets": total,
            "next_subset": if subset >= total { 1 } else { subset + 1 },
            "cycle_completed": subset >= total,
            "backup_uuid": string(&ctx.config["backup_uuid"]), "repository_id": repo,
            "snapshot_id": snapshot_id, "backend_revision": BACKEND_REVISION,
        }))?;
    }
    let message = if supported {
        format!("Repository structure and data subset {subset}/{total} verified.")
    } else {
        "Repository structure verified; this Restic build does not expose data-subset verification."
            .into()
    };
    ctx.marker(
        "restic-check-ok.json",
        json!({
            "ok": true, "time": now(), "detail": message, "verification_mode": mode,
            "backup_uuid": string(&ctx.config["backup_uuid"]), "repository_id": repo,
            "snapshot_id": snapshot_id, "backend_revision": BACKEND_REVISION,
        }),
    )?;
    ctx.success_message = Some(message.clone());
    ctx.record(
        "check",
        "Restic repository verification completed",
        &message,
        "success",
    )
}

fn restore_test(ctx: &mut Context<'_>) -> Result<(), String> {
    ctx.phase("Verifying backup disk")?;
    verify_mount(&ctx.config)?;
    let repo = ctx.repository_id()?;
    let latest = ctx
        .latest_snapshot()?
        .ok_or("No Restic snapshot matches the configured machine/scope.")?;
    let id = string(&latest["id"]);
    let short = nonempty(&latest["short_id"], &id.chars().take(8).collect::<String>());
    let test_path = nonempty(&ctx.config["restore_test_path"], "/etc/hostname")
        .trim()
        .to_owned();
    let path = Path::new(&test_path);
    if !path.is_absolute()
        || test_path == "/"
        || path
            .components()
            .any(|component| !matches!(component, Component::RootDir | Component::Normal(_)))
    {
        return Err("restore_test_path must be one absolute file path.".into());
    }
    let temporary = std::env::temp_dir().join(format!(
        "backup-recovery-restore-test-{}-{}",
        std::process::id(),
        now()
    ));
    fs::create_dir(&temporary).map_err(|error| error.to_string())?;
    let result = (|| -> Result<(), String> {
        let target = temporary.to_string_lossy().into_owned();
        ctx.phase(&format!("Restoring {test_path} from {short}"))?;
        let output = ctx.restic(
            &["restore", &id, "--target", &target, "--include", &test_path],
            900,
        );
        let restored = temporary.join(test_path.trim_start_matches('/'));
        let detail = output.detail();
        if output.code != 0 || !restored.is_file() {
            let tail: String = detail
                .chars()
                .rev()
                .take(1000)
                .collect::<String>()
                .chars()
                .rev()
                .collect();
            ctx.marker("restore-test-ok.json", json!({
                "ok": false, "time": now(), "detail": if tail.is_empty() { format!("{test_path} was not restored.") } else { tail },
                "backup_uuid": string(&ctx.config["backup_uuid"]), "repository_id": repo,
                "snapshot_id": id, "test_path": test_path, "backend_revision": BACKEND_REVISION,
            }))?;
            return Err("Restic restore verification failed.".into());
        }
        ctx.phase("Validating restored content")?;
        let dump = ctx.restic(&["dump", &id, &test_path], 300);
        let bytes = fs::read(&restored).map_err(|error| error.to_string())?;
        if dump.code != 0 || dump.stdout != bytes {
            let detail = dump.err();
            let tail: String = detail
                .chars()
                .rev()
                .take(1000)
                .collect::<String>()
                .chars()
                .rev()
                .collect();
            ctx.marker("restore-test-ok.json", json!({
                "ok": false, "time": now(),
                "detail": if tail.is_empty() { "Restored bytes did not match the snapshot stream.".into() } else { tail },
                "backup_uuid": string(&ctx.config["backup_uuid"]), "repository_id": repo,
                "snapshot_id": id, "test_path": test_path, "backend_revision": BACKEND_REVISION,
            }))?;
            return Err("Restic restore verification content check failed.".into());
        }
        let digest = run("sha256sum", &[&restored.to_string_lossy()], 30);
        if digest.code != 0 {
            return Err("Unable to hash restored file.".into());
        }
        let hash = digest
            .out()
            .split_whitespace()
            .next()
            .unwrap_or("")
            .to_owned();
        if hash.len() != 64 {
            return Err("Unable to hash restored file.".into());
        }
        let message =
            format!("{test_path} restored from snapshot {short} and matched the snapshot stream.");
        ctx.marker("restore-test-ok.json", json!({
            "ok": true, "time": now(), "detail": message,
            "backup_uuid": string(&ctx.config["backup_uuid"]), "repository_id": repo,
            "snapshot_id": id, "snapshot_time": string(&latest["time"]),
            "test_path": test_path, "restored_sha256": hash, "backend_revision": BACKEND_REVISION,
        }))?;
        ctx.success_message = Some(message);
        ctx.record(
            "restore-test",
            "Restore test passed",
            &format!(
                "{test_path} restored from {short}; SHA-256 {}… verified.",
                &hash[..12]
            ),
            "success",
        )
    })();
    let _ = fs::remove_dir_all(&temporary);
    result
}

fn smart(ctx: &Context<'_>, kind: &str) -> Result<(), String> {
    ctx.phase(&format!("Starting SMART {kind} self-test"))?;
    let disk = resolve_disk(&string(&ctx.config["backup_uuid"]), ctx.paths)?;
    let output = run("smartctl", &["-t", kind, &disk], 30);
    let text = format!("{}\n{}", output.out(), output.err())
        .trim()
        .to_owned();
    let low = text.to_lowercase();
    let accepted = [
        "please wait",
        "testing has begun",
        "self-test routine in progress",
        "test will complete",
        "successful",
    ]
    .iter()
    .any(|token| low.contains(token));
    if output.code != 0 && !accepted {
        return Err(if text.is_empty() {
            format!("SMART {kind} test could not start.")
        } else {
            text
        });
    }
    let name = if kind == "short" { "Short" } else { "Extended" };
    let tail: String = text
        .chars()
        .rev()
        .take(600)
        .collect::<String>()
        .chars()
        .rev()
        .collect();
    ctx.record(
        "smart",
        &format!("{name} SMART test started"),
        if tail.is_empty() {
            "Self-test accepted by drive."
        } else {
            &tail
        },
        "info",
    )
}

fn mount(ctx: &Context<'_>) -> Result<(), String> {
    ctx.phase("Mounting verified backup filesystem")?;
    let mountpoint = string(&ctx.config["mountpoint"]);
    let uuid = string(&ctx.config["backup_uuid"]);
    if !ctx.paths.at("/dev/disk/by-uuid").join(&uuid).exists() {
        return Err("Backup HDD is not connected.".into());
    }
    if run("mountpoint", &["-q", &mountpoint], 5).code == 0 {
        verify_mount(&ctx.config)?;
        return ctx.record("disk", "Backup disk already mounted", &mountpoint, "info");
    }
    let output = run("mount", &[&mountpoint], 30);
    if output.code != 0 {
        return Err(if output.detail().is_empty() {
            "Unable to mount backup HDD.".into()
        } else {
            output.detail()
        });
    }
    if let Err(error) = verify_mount(&ctx.config) {
        let _ = run("umount", &[&mountpoint], 30);
        return Err(error);
    }
    ctx.record(
        "disk",
        "Backup disk mounted",
        &format!("{mountpoint} · UUID {uuid}"),
        "success",
    )
}

fn busy_backup_units() -> Vec<String> {
    const UNITS: &[&str] = &[
        "restic-system-backup.service",
        "restic-maintenance.service",
        "backup-recovery-backup.service",
        "backup-recovery-timeshift.service",
        "backup-recovery-restic-check.service",
        "backup-recovery-restore-test.service",
        "backup-recovery-refresh-manifests.service",
        "backup-recovery-smart-short.service",
        "backup-recovery-smart-long.service",
    ];
    UNITS
        .iter()
        .filter(|unit| {
            matches!(
                run("systemctl", &["is-active", unit], 5).out().trim(),
                "active" | "activating"
            )
        })
        .map(|unit| (*unit).into())
        .collect()
}

fn smart_running(ctx: &Context<'_>) -> bool {
    let Ok(disk) = resolve_disk(&string(&ctx.config["backup_uuid"]), ctx.paths) else {
        return false;
    };
    let output = run("smartctl", &["-a", &disk], 20);
    let low = format!("{}\n{}", output.out(), output.err()).to_lowercase();
    low.contains("self-test routine in progress")
        || (low.contains("self-test execution status:") && low.contains("in progress"))
}

fn eject(ctx: &Context<'_>) -> Result<(), String> {
    ctx.phase("Checking active backup work")?;
    let busy = busy_backup_units();
    if !busy.is_empty() {
        return Err(format!(
            "Cannot unmount while backup work is active: {}",
            busy.join(", ")
        ));
    }
    if smart_running(ctx) {
        return Err("Cannot safely eject while the backup drive is running a SMART self-test. Wait for the drive test to finish or explicitly abort it first.".into());
    }
    let mountpoint = string(&ctx.config["mountpoint"]);
    if run("mountpoint", &["-q", &mountpoint], 5).code != 0 {
        return ctx.record(
            "disk",
            "Backup disk already unmounted",
            "It is safe to disconnect the HDD.",
            "info",
        );
    }
    verify_mount(&ctx.config)?;
    ctx.phase("Syncing filesystem buffers")?;
    if run("sync", &[], 60).code != 0 {
        return Err("Filesystem sync failed; the backup disk was not unmounted.".into());
    }
    ctx.phase("Unmounting backup filesystem")?;
    let output = run("umount", &[&mountpoint], 60);
    if output.code != 0 {
        return Err(if output.detail().is_empty() {
            "Unable to unmount backup HDD.".into()
        } else {
            output.detail()
        });
    }
    if run("mountpoint", &["-q", &mountpoint], 5).code == 0 {
        return Err(
            "Unmount command returned success but the backup filesystem is still mounted.".into(),
        );
    }
    ctx.record(
        "disk",
        "Backup disk safely unmounted",
        "Filesystem synced and unmounted. It is safe to disconnect the HDD.",
        "success",
    )
}

fn secure_dir(path: &Path, cfg: &Value, real_system: bool) -> Result<(), String> {
    if path.is_symlink() {
        return Err(format!(
            "Refusing symlinked recovery directory: {}",
            path.display()
        ));
    }
    fs::create_dir_all(path).map_err(|error| error.to_string())?;
    if !path.is_dir() || path.is_symlink() {
        return Err(format!("Unsafe recovery directory: {}", path.display()));
    }
    let user = string(&cfg["user"]).trim().to_owned();
    if user.is_empty() {
        return Err("Desktop user is not configured.".into());
    }
    if real_system {
        let (_, gid, _) = user_ids(&user)?;
        chown_root_group(path, gid, 0o750)?;
    }
    Ok(())
}

fn secure_write(path: &Path, bytes: &[u8], cfg: &Value, real_system: bool) -> Result<(), String> {
    secure_dir(
        path.parent().ok_or("File path has no parent")?,
        cfg,
        real_system,
    )?;
    atomic_bytes(path, bytes, 0o640)?;
    if real_system {
        let user = string(&cfg["user"]);
        let (_, gid, _) = user_ids(user.trim())?;
        chown_root_group(path, gid, 0o640)?;
    }
    Ok(())
}

fn secure_copy(source: &Path, target: &Path, cfg: &Value, real_system: bool) -> Result<(), String> {
    if !source.is_file() {
        return Ok(());
    }
    let bytes = fs::read(source).map_err(|error| error.to_string())?;
    secure_write(target, &bytes, cfg, real_system)
}

fn refresh_manifests(ctx: &Context<'_>) -> Result<(), String> {
    ctx.phase("Verifying backup disk")?;
    let mountpoint = verify_mount(&ctx.config)?;
    ctx.phase("Refreshing recovery manifests")?;
    let user = string(&ctx.config["user"]).trim().to_owned();
    if user.is_empty() {
        return Err("Desktop user is not configured.".into());
    }
    let (uid, _, home) = user_ids(&user)?;
    let arch = Path::new(&mountpoint).join("arch-state");
    let recovery = Path::new(&mountpoint).join("recovery");
    secure_dir(&arch, &ctx.config, ctx.paths.real_system())?;
    secure_dir(&recovery, &ctx.config, ctx.paths.real_system())?;
    let commands: &[(&str, &str, &[&str])] = &[
        ("packages-explicit.txt", "pacman", &["-Qqe"]),
        ("packages-official.txt", "pacman", &["-Qqen"]),
        ("packages-aur.txt", "pacman", &["-Qqem"]),
        ("all-packages.txt", "pacman", &["-Q"]),
        (
            "system-services-enabled.txt",
            "systemctl",
            &["list-unit-files", "--state=enabled", "--no-legend"],
        ),
        ("kernel.txt", "uname", &["-a"]),
        ("lsblk.txt", "lsblk", &["-f"]),
    ];
    for (name, program, args) in commands {
        let output = run(program, args, 60);
        if output.code != 0 {
            return Err(format!("{name}: {}", output.detail()));
        }
        secure_write(
            &arch.join(name),
            &output.stdout,
            &ctx.config,
            ctx.paths.real_system(),
        )?;
    }
    let env = vec![
        ("HOME".into(), home),
        ("USER".into(), user.clone()),
        ("LOGNAME".into(), user.clone()),
        ("XDG_RUNTIME_DIR".into(), format!("/run/user/{uid}")),
        (
            "DBUS_SESSION_BUS_ADDRESS".into(),
            format!("unix:path=/run/user/{uid}/bus"),
        ),
    ];
    let output = run_env(
        "runuser",
        &[
            "-u",
            &user,
            "--",
            "systemctl",
            "--user",
            "list-unit-files",
            "--state=enabled",
            "--no-legend",
        ],
        30,
        &env,
    );
    if output.code == 0 {
        secure_write(
            &arch.join("user-services-enabled.txt"),
            &output.stdout,
            &ctx.config,
            ctx.paths.real_system(),
        )?;
    }
    secure_copy(
        Path::new("/etc/fstab"),
        &arch.join("fstab.txt"),
        &ctx.config,
        ctx.paths.real_system(),
    )?;
    const COPIES: &[(&str, &str)] = &[
        ("/etc/fstab", "fstab-current.txt"),
        ("/etc/timeshift/timeshift.json", "timeshift.json"),
        ("/etc/restic/excludes.txt", "restic-excludes.txt"),
        (
            "/etc/systemd/system/restic-system-backup.service",
            "restic-system-backup.service",
        ),
        (
            "/etc/systemd/system/restic-system-backup.timer",
            "restic-system-backup.timer",
        ),
        (
            "/etc/systemd/system/restic-maintenance.service",
            "restic-maintenance.service",
        ),
        (
            "/etc/systemd/system/restic-maintenance.timer",
            "restic-maintenance.timer",
        ),
    ];
    for (source, target) in COPIES {
        secure_copy(
            Path::new(source),
            &recovery.join(target),
            &ctx.config,
            ctx.paths.real_system(),
        )?;
    }
    ctx.record(
        "recovery",
        "Recovery metadata refreshed",
        "Package manifests and recovery configuration were updated.",
        "success",
    )
}

fn dispatch(ctx: &mut Context<'_>) -> Result<(), String> {
    match ctx.name {
        "backup" => backup(ctx),
        "timeshift" => timeshift(ctx),
        "restic-check" => restic_check(ctx),
        "restore-test" | "bootstrap-verify" => restore_test(ctx),
        "smart-short" => smart(ctx, "short"),
        "smart-long" => smart(ctx, "long"),
        "mount" => mount(ctx),
        "eject" => eject(ctx),
        "refresh-manifests" => refresh_manifests(ctx),
        name => Err(format!("Unsupported action: {name}")),
    }
}

pub fn run_action(paths: &Paths, name: &str) -> Result<(), String> {
    let cfg = read_json(&paths.config(), json!({}));
    if !boolish(&cfg) {
        return Err("Backup Recovery configuration is missing.".into());
    }
    let started = now();
    let lock_path = paths.at("/run/backup-recovery/storage.lock");
    let lock = Lock::acquire(&lock_path, true);
    let result = match lock {
        Err(_) => {
            let state = read_json(&paths.state("action-state.json"), json!({}));
            Err(format!(
                "Busy: {} is already in progress.",
                nonempty(&state["action"], "another backup/recovery action")
            ))
        }
        Ok(_guard) => {
            let busy: Vec<&str> = ["restic-system-backup.service", "restic-maintenance.service"]
                .iter()
                .copied()
                .filter(|unit| {
                    matches!(
                        run("systemctl", &["is-active", unit], 5).out().trim(),
                        "active" | "activating"
                    )
                })
                .collect();
            if !busy.is_empty() {
                Err(format!(
                    "Busy: external backup work is active: {}",
                    busy.join(", ")
                ))
            } else {
                let mut ctx = Context {
                    paths,
                    config: cfg.clone(),
                    name,
                    started,
                    success_message: None,
                };
                let result = (|| -> Result<(), String> {
                    ctx.publish("running", "Preparing action", json!({}), "", None)?;
                    let title = format!("{} started", label(name));
                    notify(
                        &cfg,
                        "start",
                        name,
                        &title,
                        "Backup & Recovery is running this operation in the background.",
                        "low",
                    );
                    dispatch(&mut ctx)?;
                    let message = ctx
                        .success_message
                        .clone()
                        .unwrap_or_else(|| format!("{name} completed successfully."));
                    ctx.publish("success", "Completed", json!({}), &message, Some(now()))?;
                    let title = format!("{} completed", label(name));
                    notify(
                        &cfg,
                        "success",
                        name,
                        &title,
                        &format!("{message} · {}", duration(now() - started)),
                        "normal",
                    );
                    Ok(())
                })();
                if let Err(ref error) = result {
                    let _ = ctx.publish("failed", "Failed", json!({}), error, Some(now()));
                }
                result
            }
        }
    };
    if let Err(ref error) = result {
        let _ = record(paths, name, &format!("{name} failed"), error, "error");
        if !error.starts_with("Busy:") {
            let title = format!("{} failed", label(name));
            notify(
                &cfg,
                "failure",
                name,
                &title,
                &format!("{error} · after {}", duration(now() - started)),
                "critical",
            );
        }
    }
    // Retain the last result even if the follow-up state refresh fails.
    let _ = collector::collect_state(paths, false);
    result
}
