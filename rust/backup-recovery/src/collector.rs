use crate::root_common::{
    age_hours, atomic_json, boolish, chown_root_group, file_mtime, freshness, hostname, merge,
    nonempty, now, number, read_json, run, string, user_ids, Lock, Paths, BACKEND_REVISION,
    SCHEMA_VERSION, UI_CONTRACT,
};
use chrono::DateTime;
use regex::Regex;
use serde_json::{json, Value};
use std::fs;
use std::path::{Path, PathBuf};

fn systemctl_show(unit: &str) -> Value {
    let output = run(
        "systemctl",
        &[
            "show",
            unit,
            "--no-pager",
            "--property=LoadState,ActiveState,SubState,UnitFileState,Result,ExecMainStatus,ActiveEnterTimestamp,InactiveEnterTimestamp,NextElapseUSecRealtime,LastTriggerUSec",
        ],
        8,
    );
    let mut data = json!({"unit": unit, "available": output.code == 0});
    for line in output.out().lines() {
        if let Some((key, value)) = line.split_once('=') {
            data[key] = json!(value);
        }
    }
    data
}

fn device(uuid: &str, paths: &Paths) -> Value {
    let link = paths.at("/dev/disk/by-uuid").join(uuid);
    let mut connected = link.exists();
    let mut part = String::new();
    let mut disk = String::new();
    let mut model = String::new();
    let mut size = String::new();
    let mut transport = String::new();
    let mut removable = false;
    let mut hotplug = false;
    if connected {
        match fs::canonicalize(&link) {
            Ok(path) => part = path.to_string_lossy().into_owned(),
            Err(_) => connected = false,
        }
    }
    if !part.is_empty() {
        let parent = run("lsblk", &["-ndo", "PKNAME", &part], 5)
            .out()
            .trim()
            .to_owned();
        if !parent.is_empty() {
            disk = format!("/dev/{parent}");
            model = run("lsblk", &["-dno", "MODEL", &disk], 5)
                .out()
                .trim()
                .into();
            size = run("lsblk", &["-dno", "SIZE", &disk], 5)
                .out()
                .trim()
                .into();
            transport = run("lsblk", &["-dno", "TRAN", &disk], 5)
                .out()
                .trim()
                .into();
            removable = run("lsblk", &["-dno", "RM", &disk], 5).out().trim() == "1";
            hotplug = run("lsblk", &["-dno", "HOTPLUG", &disk], 5).out().trim() == "1";
        }
    }
    json!({
        "uuid": uuid, "connected": connected, "partition": part, "disk": disk,
        "model": model, "size": size, "transport": transport,
        "removable": removable, "hotplug": hotplug,
    })
}

fn mount_state(mountpoint: &str, mut device: Value) -> Value {
    let output = run(
        "findmnt",
        &["-rn", "-o", "SOURCE,FSTYPE,OPTIONS,UUID", mountpoint],
        5,
    );
    let mounted = output.code == 0 && !output.out().trim().is_empty();
    let fields: Vec<String> = output
        .out()
        .split_whitespace()
        .take(4)
        .map(str::to_owned)
        .collect();
    let field = |index: usize| fields.get(index).cloned().unwrap_or_default();
    let (mut total, mut used, mut free) = (0u64, 0u64, 0u64);
    let mut accessible = false;
    if mounted {
        if let Ok(cpath) = std::ffi::CString::new(mountpoint) {
            let mut info: libc::statvfs = unsafe { std::mem::zeroed() };
            if unsafe { libc::statvfs(cpath.as_ptr(), &mut info) } == 0 {
                total = info.f_blocks.saturating_mul(info.f_frsize);
                free = info.f_bavail.saturating_mul(info.f_frsize);
                used = total.saturating_sub(info.f_bfree.saturating_mul(info.f_frsize));
                accessible = true;
            }
        }
    }
    let status = if mounted {
        if accessible {
            "mounted"
        } else {
            "mounted-unavailable"
        }
    } else if device["connected"] == true {
        "connected-unmounted"
    } else {
        "offline"
    };
    merge(
        &mut device,
        &json!({
            "mounted": mounted, "status": status, "filesystem_accessible": accessible,
            "mountpoint": mountpoint, "source": field(0), "fstype": field(1),
            "options": field(2), "mounted_uuid": field(3),
            "total_bytes": total, "used_bytes": used, "free_bytes": free,
            "used_percent": if total == 0 { 0.0 } else {
                (((used as f64 / total as f64) * 100.0) * 10.0).round() / 10.0
            },
        }),
    );
    device
}

fn enforce_mount_identity(disk: &mut Value, uuid: &str) -> Result<(), String> {
    if uuid.trim().is_empty() {
        return Err("Backup filesystem UUID is not configured.".into());
    }
    let mounted = disk["mounted"] == true;
    let mounted_uuid = string(&disk["mounted_uuid"]).trim().to_owned();
    let raw_accessible = disk["filesystem_accessible"] == true;
    let verified = mounted && !mounted_uuid.is_empty() && mounted_uuid == uuid;
    disk["mounted_identity_verified"] = json!(verified);
    disk["identity_verified"] = json!(disk["connected"] == true && (!mounted || verified));
    disk["raw_filesystem_accessible"] = json!(raw_accessible);
    disk["filesystem_accessible"] = json!(raw_accessible && verified);
    if mounted && !verified {
        disk["status"] = json!("wrong-filesystem-mounted");
    }
    Ok(())
}

fn restic_base<'a>(repo: &'a str, password: &'a str, cache: &'a str) -> [&'a str; 6] {
    [
        "-r",
        repo,
        "--password-file",
        password,
        "--cache-dir",
        cache,
    ]
}

fn restic_snapshots(
    repo: &str,
    password: &str,
    cache: &str,
    hostname: &str,
    required_tags: &[String],
    required_paths: &[String],
) -> Result<Value, String> {
    let base = restic_base(repo, password, cache);
    let args: Vec<&str> = base.into_iter().chain(["snapshots", "--json"]).collect();
    let output = run("restic", &args, 60);
    if output.code != 0 {
        return Err(output.detail());
    }
    let rows: Value = serde_json::from_slice(&output.stdout)
        .map_err(|error| format!("Invalid Restic JSON: {error}"))?;
    let mut snapshots = Vec::new();
    let mut repository_count = 0;
    for row in rows
        .as_array()
        .ok_or("Restic snapshot response is not an array")?
    {
        if !row.is_object() {
            continue;
        }
        repository_count += 1;
        let host = string(&row["hostname"]);
        let tags = strings(&row["tags"]);
        let paths = strings(&row["paths"]);
        if !hostname.is_empty() && host != hostname {
            continue;
        }
        if !required_tags.iter().all(|tag| tags.contains(tag))
            || !required_paths.iter().all(|path| paths.contains(path))
        {
            continue;
        }
        let id = string(&row["id"]);
        let mut short = nonempty(&row["short_id"], &id);
        short.truncate(short.len().min(8));
        snapshots.push(json!({
            "id": id, "short_id": short, "time": string(&row["time"]),
            "hostname": host, "tags": tags, "paths": paths,
        }));
    }
    snapshots.sort_by(|a, b| string(&b["time"]).cmp(&string(&a["time"])));
    Ok(json!({
        "known": true, "scope_version": 1,
        "scope": {"hostname": hostname, "required_tags": required_tags, "required_paths": required_paths},
        "repository_snapshot_count": repository_count,
        "count": snapshots.len(), "latest": snapshots.first(), "snapshots": snapshots,
    }))
}

fn repository_id(repo: &str, password: &str, cache: &str) -> Result<String, String> {
    let base = restic_base(repo, password, cache);
    let args: Vec<&str> = base.into_iter().chain(["cat", "config"]).collect();
    let output = run("restic", &args, 60);
    if output.code != 0 {
        return Err(output.detail());
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

fn strings(value: &Value) -> Vec<String> {
    value.as_array().map_or_else(Vec::new, |items| {
        items
            .iter()
            .map(string)
            .filter(|text| !text.is_empty())
            .collect()
    })
}

fn cached_domain(evidence: &Value, name: &str) -> Option<Value> {
    let item = evidence.get(name)?;
    if !item.is_object() || !boolish(&item["known"]) {
        return None;
    }
    let mut item = item.clone();
    item["availability"] = json!("cached");
    item["cached"] = json!(true);
    Some(item)
}

fn save_domain(evidence: &mut Value, name: &str, payload: &Value) {
    let mut data = payload.clone();
    data["known"] = json!(true);
    data["verified_at"] = json!(now());
    if let Some(map) = data.as_object_mut() {
        for key in ["availability", "cached", "current_error"] {
            map.remove(key);
        }
    }
    evidence[name] = data;
}

fn timeshift_config(paths: &Paths) -> Value {
    let data = read_json(&paths.at("/etc/timeshift/timeshift.json"), json!({}));
    let enabled = |name: &str| string(&data[name]).to_lowercase() == "true";
    json!({
        "configured": boolish(&data),
        "mode": if enabled("btrfs_mode") { "BTRFS" } else { "RSYNC" },
        "schedule": {
            "daily": enabled("schedule_daily"), "daily_keep": number(&data["count_daily"]),
            "weekly": enabled("schedule_weekly"), "weekly_keep": number(&data["count_weekly"]),
        },
    })
}

fn timeshift_snapshots(mountpoint: &str) -> Value {
    let root = Path::new(mountpoint).join("timeshift/snapshots");
    let mut paths: Vec<PathBuf> = fs::read_dir(root)
        .ok()
        .into_iter()
        .flatten()
        .filter_map(Result::ok)
        .map(|item| item.path())
        .filter(|path| path.is_dir())
        .collect();
    paths.sort_by(|a, b| b.cmp(a));
    let rows: Vec<Value> = paths
        .iter()
        .map(|path| {
            let info = read_json(&path.join("info.json"), json!({}));
            json!({
                "name": path.file_name().unwrap_or_default().to_string_lossy(),
                "comments": nonempty(&info["comments"], &string(&info["comment"])),
                "tags": string(&info["tags"]), "created_at": file_mtime(path),
            })
        })
        .collect();
    json!({"known": true, "count": rows.len(), "latest": rows.first(), "snapshots": rows})
}

fn status_label(status: &str) -> String {
    let low = status.to_lowercase();
    for (needle, label) in [
        ("completed without error", "Passed"),
        ("aborted by host", "Aborted by host/system"),
        ("interrupted", "Interrupted"),
        ("in progress", "Running"),
        ("failure", "Failed"),
        ("failed", "Failed"),
    ] {
        if low.contains(needle) {
            return label.into();
        }
    }
    let trimmed = status.trim();
    if trimmed.is_empty() {
        "Unknown".into()
    } else {
        trimmed.into()
    }
}

fn regex_capture(text: &str, pattern: &str) -> Option<String> {
    Regex::new(pattern)
        .ok()?
        .captures(text)?
        .get(1)
        .map(|match_| match_.as_str().into())
}

fn smart_text(text: &str) -> Value {
    let health = regex_capture(
        text,
        r"SMART overall-health self-assessment test result:\s*(\S+)",
    )
    .unwrap_or_else(|| "unknown".into())
    .to_lowercase();
    let mut attrs = json!({});
    let mut temperature = Value::Null;
    for line in text.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() < 10 || !parts[0].chars().all(|char_| char_.is_ascii_digit()) {
            continue;
        }
        let target = match parts[1] {
            "Reallocated_Sector_Ct" => "reallocated",
            "Current_Pending_Sector" => "pending",
            "Offline_Uncorrectable" => "uncorrectable",
            "UDMA_CRC_Error_Count" => "crc_errors",
            "Power_On_Hours" => "power_on_hours",
            "Load_Cycle_Count" => "load_cycles",
            _ => "",
        };
        if !target.is_empty() {
            attrs[target] = parts[9]
                .parse::<i64>()
                .map_or_else(|_| json!(parts[9]), |value| json!(value));
        }
        if temperature.is_null()
            && matches!(parts[1], "Temperature_Celsius" | "Airflow_Temperature_Cel")
        {
            if let Ok(value) = parts[9].parse::<i64>() {
                temperature = json!(value);
            }
        }
    }
    if temperature.is_null() {
        temperature = regex_capture(text, r"Current Drive Temperature:\s*(\d+)\s*C")
            .and_then(|text| text.parse::<i64>().ok())
            .map_or(Value::Null, |value| json!(value));
    }
    let errors = regex_capture(text, r"ATA Error Count:\s*(\d+)")
        .and_then(|text| text.parse::<i64>().ok())
        .map_or(Value::Null, |value| json!(value));
    let duration = |pattern: &str| {
        regex_capture(text, pattern)
            .and_then(|text| text.parse::<i64>().ok())
            .map_or(Value::Null, |value| json!(value))
    };
    let short = duration(
        r"(?is)Short self-test routine\s+recommended polling time:\s*\(\s*(\d+)\)\s*minutes?",
    );
    let extended = duration(
        r"(?is)Extended self-test routine\s+recommended polling time:\s*\(\s*(\d+)\)\s*minutes?",
    );
    let test_pattern =
        Regex::new(r"^\s*#\s*(\d+)\s+(.+?)\s{2,}(.+?)\s{2,}(\d+)%\s+(\d+)\s+(\S+)\s*$").unwrap();
    let mut tests = Vec::new();
    for line in text.lines() {
        if let Some(captures) = test_pattern.captures(line) {
            let part = |index: usize| captures.get(index).map_or("", |item| item.as_str());
            let remaining = part(4).parse::<i64>().unwrap_or(0);
            let status = part(3).trim();
            tests.push(json!({
                "number": part(1).parse::<i64>().unwrap_or(0),
                "type": part(2).trim(), "status": status, "status_label": status_label(status),
                "remaining_percent": remaining, "completed_percent": (100 - remaining).clamp(0,100),
                "lifetime_hours": part(5).parse::<i64>().unwrap_or(0),
                "lba": part(6), "raw": line.trim(),
            }));
            if tests.len() >= 8 {
                break;
            }
        }
    }
    let bad =
        number(&attrs["reallocated"]) + number(&attrs["pending"]) + number(&attrs["uncorrectable"]);
    let condition = if health == "unknown" {
        "unverified"
    } else if health != "passed" || bad > 0 {
        "critical"
    } else if number(&errors) > 0 {
        "history-warning"
    } else {
        "healthy"
    };
    json!({
        "known": true, "available": true, "health": health, "condition": condition,
        "temperature_c": temperature, "attributes": attrs, "historical_error_count": errors,
        "last_test": tests.first(), "self_tests": tests,
        "test_durations": {"short_minutes": short, "extended_minutes": extended},
    })
}

fn parse_smart(disk: &str) -> Result<Value, String> {
    if disk.is_empty() {
        return Err("Physical backup disk is unavailable.".into());
    }
    let output = run("smartctl", &["-a", disk], 20);
    let text = format!("{}\n{}", output.out(), output.err());
    if !text.contains("SMART support is: Available") && !text.contains("SMART overall-health") {
        let detail = text.trim();
        return Err(if detail.is_empty() {
            "SMART data unavailable.".into()
        } else {
            detail
                .chars()
                .rev()
                .take(700)
                .collect::<String>()
                .chars()
                .rev()
                .collect()
        });
    }
    Ok(smart_text(&text))
}

fn etc_history(paths: &Paths) -> Value {
    if !paths.at("/etc/.git").exists() {
        return json!({"available": false, "clean": false, "latest": null, "changed_count": null});
    }
    let status = run("git", &["-C", "/etc", "status", "--porcelain"], 12);
    let log = run(
        "git",
        &["-C", "/etc", "log", "-1", "--format=%H%x1f%h%x1f%ct%x1f%s"],
        8,
    );
    let output = log.out();
    let parts: Vec<&str> = output.trim().splitn(4, '\u{1f}').collect();
    let latest = if log.code == 0 && parts.len() == 4 {
        json!({"id": parts[0], "short_id": parts[1], "timestamp": parts[2].parse::<i64>().unwrap_or(0), "subject": parts[3]})
    } else {
        Value::Null
    };
    let count = status
        .out()
        .lines()
        .filter(|line| !line.trim().is_empty())
        .count();
    json!({
        "available": status.code == 0, "clean": status.code == 0 && count == 0,
        "changed_count": if status.code == 0 { json!(count) } else { Value::Null },
        "latest": latest,
    })
}

fn activity(paths: &Paths) -> Value {
    let data = read_json(&paths.state("activity.json"), json!([]));
    let Some(mut rows) = data.as_array().cloned() else {
        return json!([]);
    };
    rows.sort_by_key(|item| std::cmp::Reverse(number(&item["time"])));
    rows.truncate(30);
    json!(rows)
}

fn iso_timestamp(text: &str) -> i64 {
    DateTime::parse_from_rfc3339(text).map_or(0, |datetime| datetime.timestamp())
}

fn marker(path: &Path) -> Value {
    if !path.exists() {
        return json!({"known": false, "ok": null, "time": 0, "detail": ""});
    }
    let raw = read_json(path, json!({}));
    if !raw.get("ok").is_some() {
        json!({"known": false, "ok": null, "time": number(&raw["time"]), "detail": string(&raw["detail"])})
    } else {
        json!({"known": true, "ok": boolish(&raw["ok"]), "time": number(&raw["time"]), "detail": string(&raw["detail"])})
    }
}

fn marker_provenance(
    path: &Path,
    overdue: i64,
    uuid: &str,
    repository: &str,
    snapshot: &str,
) -> Value {
    let mut result = marker(path);
    let age = age_hours(number(&result["time"]));
    result["age_hours"] = age.clone();
    result["overdue_hours"] = json!(overdue);
    result["freshness"] = json!(if result["known"] == true {
        freshness(&age, overdue)
    } else {
        "unknown"
    });
    result["fresh"] = json!(result["known"] == true && result["freshness"] == "fresh");
    if result["known"] != true {
        merge(
            &mut result,
            &json!({"identity_valid": null, "snapshot_current": null, "provenance_state": "unknown"}),
        );
        return result;
    }
    let raw = read_json(path, json!({}));
    let marker_uuid = string(&raw["backup_uuid"]);
    let marker_repo = string(&raw["repository_id"]);
    let marker_snapshot = string(&raw["snapshot_id"]);
    let identity = !marker_uuid.is_empty()
        && marker_uuid == uuid
        && (repository.is_empty() || (!marker_repo.is_empty() && marker_repo == repository));
    let snapshot_current = if snapshot.is_empty() {
        Value::Null
    } else {
        json!(!marker_snapshot.is_empty() && marker_snapshot == snapshot)
    };
    merge(&mut result, &raw);
    result["identity_valid"] = json!(identity);
    result["snapshot_current"] = snapshot_current.clone();
    if !identity {
        result["provenance_state"] = json!("identity-mismatch");
        result["fresh"] = json!(false);
        result["freshness"] = json!("invalid");
    } else if snapshot_current == false {
        result["provenance_state"] = json!("superseded");
        result["fresh"] = json!(false);
        result["freshness"] = json!("superseded");
    } else {
        result["provenance_state"] = json!("current");
    }
    result
}

fn attestation(path: &Path, overdue: i64, uuid: &str, repository: &str) -> Value {
    let raw = read_json(path, json!({}));
    if raw["verified"] != true {
        return json!({
            "known": false, "verified": false, "verified_at": 0,
            "label": "", "identifier": "", "age_hours": null,
            "overdue_hours": overdue, "freshness": "unknown",
            "fresh": false, "identity_valid": null,
        });
    }
    let timestamp = number(&raw["verified_at"]);
    let age = age_hours(timestamp);
    let identity = (uuid.is_empty() || string(&raw["backup_uuid"]) == uuid)
        && (repository.is_empty() || string(&raw["repository_id"]) == repository);
    let state = if identity {
        freshness(&age, overdue)
    } else {
        "invalid"
    };
    let mut result = raw;
    merge(
        &mut result,
        &json!({
            "known": true, "verified": true, "verified_at": timestamp,
            "age_hours": age, "overdue_hours": overdue, "freshness": state,
            "fresh": state == "fresh" && identity, "identity_valid": identity,
        }),
    );
    result
}

fn backup_proof(path: &Path, uuid: &str, repository: &str, snapshot: &str) -> Value {
    let raw = read_json(path, json!({}));
    if raw.get("ok").is_none() {
        return json!({"known": false, "ok": null, "current": false, "detail": ""});
    }
    let identity = string(&raw["backup_uuid"]) == uuid
        && (repository.is_empty() || string(&raw["repository_id"]) == repository);
    let current = !snapshot.is_empty() && string(&raw["snapshot_id"]) == snapshot;
    let mut result = raw;
    let accepted = result["ok"] == true && identity && current;
    let age = age_hours(number(&result["time"]));
    merge(
        &mut result,
        &json!({
            "known": true, "identity_valid": identity, "snapshot_current": current,
            "current": accepted, "age_hours": age,
        }),
    );
    result
}

fn data_check(path: &Path, uuid: &str, repository: &str) -> Value {
    let raw = read_json(path, json!({}));
    if !boolish(&raw) {
        return json!({"known": false, "ok": null, "identity_valid": null});
    }
    let identity = string(&raw["backup_uuid"]) == uuid
        && (repository.is_empty() || string(&raw["repository_id"]) == repository);
    let mut result = raw;
    let age = age_hours(number(&result["time"]));
    merge(
        &mut result,
        &json!({
            "known": true, "identity_valid": identity,
            "age_hours": age,
        }),
    );
    result
}

fn check(id: &str, label: &str, ok: bool, state: &str, detail: &str, cached: bool) -> Value {
    json!({"id": id, "label": label, "ok": ok, "state": state, "detail": detail, "cached": cached})
}

fn attention(severity: &str, tag: &str, title: &str, detail: &str) -> Value {
    json!({"severity": severity, "tag": tag, "title": title, "detail": detail})
}

fn overall(
    critical: bool,
    restic_ready: bool,
    restic_stale: bool,
    timeshift_ready: bool,
    timeshift_stale: bool,
    disk: &Value,
) -> Value {
    if critical {
        json!({"status": "critical", "label": "Needs attention",
            "summary": "A current backup, filesystem, restore-verification, or disk-health problem needs attention."})
    } else if restic_stale || timeshift_stale {
        let mut stale = Vec::new();
        if restic_stale {
            stale.push("backup");
        }
        if timeshift_stale {
            stale.push("restore point");
        }
        json!({"status": "warning", "label": "Protection due",
            "summary": format!("Protection exists, but the {} evidence is older than its configured target.", stale.join(" and "))})
    } else if restic_ready
        && timeshift_ready
        && disk["mounted_identity_verified"] == true
        && disk["filesystem_accessible"] == true
    {
        json!({"status": "protected", "label": "Protected",
            "summary": "Protection is current and the verified backup filesystem is mounted."})
    } else if restic_ready
        && timeshift_ready
        && disk["connected"] == true
        && disk["mounted"] != true
    {
        json!({"status": "protected-unmounted", "label": "Protected",
            "summary": "Protection is current; the backup HDD is connected but intentionally unmounted."})
    } else if restic_ready && timeshift_ready && disk["connected"] != true {
        json!({"status": "protected-offline", "label": "Protected",
            "summary": "Protection is current; the backup HDD is offline by design."})
    } else {
        json!({"status": "unverified", "label": "Not verified",
            "summary": "Some protection evidence is missing, stale, or has not been verified yet."})
    }
}

fn collect(paths: &Paths) -> Result<(Value, Value), String> {
    let cfg = read_json(&paths.config(), json!({}));
    if !boolish(&cfg) {
        return Err("backup-recovery config missing".into());
    }
    let mut evidence = read_json(&paths.state("evidence.json"), json!({}));
    if !evidence.is_object() {
        evidence = json!({});
    }
    let uuid = string(&cfg["backup_uuid"]);
    let mountpoint = nonempty(&cfg["mountpoint"], "/mnt/backup");
    let repo = nonempty(&cfg["restic_repo"], &format!("{mountpoint}/restic"));
    let password = nonempty(&cfg["restic_password_file"], "/etc/restic/password");
    let cache = nonempty(&cfg["restic_cache_dir"], "/var/cache/restic");
    let overdue = cfg.get("overdue_hours").map_or(48, number);
    let timeshift_overdue = cfg.get("timeshift_overdue_hours").map_or(168, number);
    let check_overdue = cfg
        .get("repository_check_overdue_hours")
        .map_or(720, number);
    let restore_overdue = cfg.get("restore_test_overdue_hours").map_or(720, number);
    let manifests_overdue = cfg.get("manifests_overdue_hours").map_or(168, number);
    let expected_host = nonempty(&cfg["restic_expected_hostname"], &hostname())
        .trim()
        .to_owned();
    let tags = strings(&cfg["restic_required_tags"]);
    let required_paths = strings(&cfg["restic_required_paths"]);
    let credential_overdue = cfg
        .get("credential_proof_overdue_hours")
        .map_or(4320, number);
    let media_overdue = cfg
        .get("recovery_media_proof_overdue_hours")
        .map_or(2160, number);
    let second_overdue = cfg
        .get("second_copy_proof_overdue_hours")
        .map_or(720, number);

    let hardware = device(&uuid, paths);
    let mut disk = mount_state(&mountpoint, hardware.clone());
    disk["expected_uuid"] = json!(uuid);
    enforce_mount_identity(&mut disk, &uuid)?;

    let repo_exists = disk["filesystem_accessible"] == true && Path::new(&repo).is_dir();
    let password_exists = Path::new(&password).is_file();
    let mut restic = if repo_exists && password_exists {
        let _ = fs::create_dir_all(&cache);
        let live = restic_snapshots(
            &repo,
            &password,
            &cache,
            &expected_host,
            &tags,
            &required_paths,
        );
        if let Ok(mut live) = live {
            match repository_id(&repo, &password, &cache) {
                Ok(repo_id) => {
                    let has_snapshots = number(&live["count"]) > 0;
                    merge(
                        &mut live,
                        &json!({
                            "repository_id": repo_id, "configured": true, "availability": "live",
                            "current_state": if has_snapshots { "ready" } else { "empty" },
                            "cached": false, "repository_accessible": true,
                            "verified_at": now(), "current_error": "",
                        }),
                    );
                    save_domain(&mut evidence, "restic", &live);
                    live
                }
                Err(error) => {
                    let mut cached = cached_domain(&evidence, "restic")
                        .filter(|item| number(&item["scope_version"]) == 1);
                    let is_cached = cached.is_some();
                    let mut value = cached.take().unwrap_or_else(|| json!({
                        "known": false, "snapshots": [], "count": null, "latest": null,
                        "scope_version": 1,
                        "scope": {"hostname": expected_host, "required_tags": tags, "required_paths": required_paths},
                    }));
                    merge(
                        &mut value,
                        &json!({
                            "configured": true, "availability": if is_cached { "cached" } else { "unavailable" },
                            "current_state": "failed", "cached": is_cached,
                            "repository_accessible": true, "current_error": error,
                        }),
                    );
                    value
                }
            }
        } else {
            let restic_error = live.err().unwrap_or_default();
            let mut cached = cached_domain(&evidence, "restic")
                .filter(|item| number(&item["scope_version"]) == 1);
            let is_cached = cached.is_some();
            let mut value = cached.take().unwrap_or_else(|| json!({
                "known": false, "snapshots": [], "count": null, "latest": null,
                "scope_version": 1,
                "scope": {"hostname": expected_host, "required_tags": tags, "required_paths": required_paths},
            }));
            merge(
                &mut value,
                &json!({
                    "configured": true, "availability": if is_cached { "cached" } else { "unavailable" },
                    "current_state": "failed", "cached": is_cached,
                    "repository_accessible": true,
                    "current_error": if restic_error.is_empty() { "Restic repository query failed." } else { &restic_error },
                }),
            );
            value
        }
    } else {
        let mut cached =
            cached_domain(&evidence, "restic").filter(|item| number(&item["scope_version"]) == 1);
        let is_cached = cached.is_some();
        let mut value = cached.take().unwrap_or_else(|| json!({
            "known": false, "snapshots": [], "count": null, "latest": null,
            "scope_version": 1,
            "scope": {"hostname": expected_host, "required_tags": tags, "required_paths": required_paths},
        }));
        let (state, error) = if !password_exists {
            ("missing-credential", "Restic password file is missing.")
        } else if disk["filesystem_accessible"] == true && !repo_exists {
            (
                "missing-repository",
                "Restic repository directory is missing on the verified backup filesystem.",
            )
        } else if disk["mounted"] == true && disk["mounted_identity_verified"] != true {
            ("blocked-identity", "Restic repository access is blocked until the mounted filesystem identity is verified.")
        } else if is_cached {
            ("cached", "")
        } else {
            ("unavailable", "")
        };
        merge(
            &mut value,
            &json!({
                "configured": password_exists, "availability": if is_cached { "cached" } else { "unavailable" },
                "current_state": state, "cached": is_cached, "repository_accessible": false, "current_error": error,
            }),
        );
        value
    };

    let timeshift_base = timeshift_config(paths);
    let mut timeshift = if disk["filesystem_accessible"] == true {
        let live = timeshift_snapshots(&mountpoint);
        let mut value = timeshift_base.clone();
        merge(&mut value, &live);
        merge(
            &mut value,
            &json!({"availability": "live", "cached": false, "verified_at": now()}),
        );
        let mut saved = live;
        merge(&mut saved, &timeshift_base);
        save_domain(&mut evidence, "timeshift", &saved);
        value
    } else {
        let cached = cached_domain(&evidence, "timeshift");
        let is_cached = cached.is_some();
        let mut value = cached.unwrap_or_else(
            || json!({"known": false, "snapshots": [], "count": null, "latest": null}),
        );
        merge(&mut value, &timeshift_base);
        merge(
            &mut value,
            &json!({"availability": if is_cached { "cached" } else { "unavailable" }, "cached": is_cached}),
        );
        value
    };

    let mut smart_error = String::new();
    let mut smart = if hardware["connected"] == true {
        match parse_smart(&string(&hardware["disk"])) {
            Ok(mut live) => {
                merge(
                    &mut live,
                    &json!({"availability": "live", "cached": false, "verified_at": now(), "current_error": ""}),
                );
                save_domain(&mut evidence, "smart", &live);
                live
            }
            Err(error) => {
                smart_error = error;
                let cached = cached_domain(&evidence, "smart");
                let is_cached = cached.is_some();
                let mut value = cached.unwrap_or_else(|| json!({"known": false, "available": false, "attributes": {}, "self_tests": [], "last_test": null, "test_durations": {}}));
                merge(
                    &mut value,
                    &json!({"availability": if is_cached { "cached" } else { "unavailable" }, "cached": is_cached, "current_error": smart_error}),
                );
                value
            }
        }
    } else {
        let cached = cached_domain(&evidence, "smart");
        let is_cached = cached.is_some();
        let mut value = cached.unwrap_or_else(|| json!({"known": false, "available": false, "attributes": {}, "self_tests": [], "last_test": null, "test_durations": {}}));
        merge(
            &mut value,
            &json!({"availability": if is_cached { "cached" } else { "unavailable" }, "cached": is_cached, "current_error": ""}),
        );
        value
    };
    smart["available"] = json!(boolish(&smart["known"]));

    let timer = systemctl_show("restic-system-backup.timer");
    let maintenance_timer = systemctl_show("restic-maintenance.timer");
    let service = systemctl_show("restic-system-backup.service");
    let state_timer = systemctl_show("backup-recovery-state.timer");

    let latest_ts = iso_timestamp(&string(&restic["latest"]["time"]));
    let restic_age = age_hours(latest_ts);
    let restic_freshness = freshness(&restic_age, overdue);
    merge(
        &mut restic,
        &json!({
            "latest_timestamp": latest_ts, "age_hours": restic_age, "overdue_hours": overdue,
            "freshness": restic_freshness, "fresh": restic_freshness == "fresh",
            "timer": timer, "maintenance_timer": maintenance_timer, "service": service,
        }),
    );
    let repo_id = string(&restic["repository_id"]);
    let snapshot_id = string(&restic["latest"]["id"]);
    restic["check"] = marker_provenance(
        &paths.state("restic-check-ok.json"),
        check_overdue,
        &uuid,
        &repo_id,
        &snapshot_id,
    );
    restic["restore_test"] = marker_provenance(
        &paths.state("restore-test-ok.json"),
        restore_overdue,
        &uuid,
        &repo_id,
        &snapshot_id,
    );
    restic["data_check"] = data_check(&paths.state("restic-data-check.json"), &uuid, &repo_id);
    restic["backup_proof"] = backup_proof(
        &paths.state("backup-proof.json"),
        &uuid,
        &repo_id,
        &snapshot_id,
    );

    let ts_latest = number(&timeshift["latest"]["created_at"]);
    let ts_age = age_hours(ts_latest);
    let ts_freshness = freshness(&ts_age, timeshift_overdue);
    merge(
        &mut timeshift,
        &json!({
            "latest_timestamp": ts_latest, "age_hours": ts_age, "overdue_hours": timeshift_overdue,
            "freshness": ts_freshness, "fresh": ts_freshness == "fresh",
        }),
    );

    let recovery_root = Path::new(&mountpoint).join("recovery");
    let arch_state = Path::new(&mountpoint).join("arch-state");
    let restore_doc = recovery_root.join("RESTORE.md");
    let manifests = arch_state.join("packages-explicit.txt");
    let mut recovery_evidence = evidence
        .get("recovery")
        .filter(|item| item.is_object())
        .cloned()
        .unwrap_or_else(|| json!({}));
    let (guide_known, manifests_known, manifests_timestamp, iso_files) =
        if disk["filesystem_accessible"] == true {
            let guide = restore_doc.is_file();
            let known = manifests.is_file();
            let timestamp = if known { file_mtime(&manifests) } else { 0 };
            let names: Vec<String> = fs::read_dir(&recovery_root)
                .ok()
                .into_iter()
                .flatten()
                .filter_map(Result::ok)
                .map(|entry| entry.path())
                .filter(|path| path.extension().is_some_and(|ext| ext == "iso"))
                .filter_map(|path| {
                    path.file_name()
                        .map(|name| name.to_string_lossy().into_owned())
                })
                .collect();
            recovery_evidence = json!({
                "known": true, "verified_at": now(), "guide_known": guide,
                "manifests_known": known, "manifests_updated_at": timestamp, "iso_files": names,
            });
            evidence["recovery"] = recovery_evidence.clone();
            (guide, known, timestamp, json!(names))
        } else {
            (
                boolish(&recovery_evidence["guide_known"]),
                boolish(&recovery_evidence["manifests_known"]),
                number(&recovery_evidence["manifests_updated_at"]),
                recovery_evidence["iso_files"]
                    .as_array()
                    .map_or_else(|| json!([]), |rows| json!(rows)),
            )
        };
    let manifests_age = age_hours(manifests_timestamp);
    let manifests_freshness = if manifests_known {
        freshness(&manifests_age, manifests_overdue)
    } else {
        "unknown"
    };
    let manifests_fresh = manifests_known && manifests_freshness == "fresh";

    let credential = attestation(
        &paths.state("credential-recovery.json"),
        credential_overdue,
        &uuid,
        &repo_id,
    );
    let media = attestation(
        &paths.state("recovery-media.json"),
        media_overdue,
        &uuid,
        "",
    );
    let second = attestation(&paths.state("second-copy.json"), second_overdue, &uuid, "");
    let credential_verified = credential["fresh"] == true;
    let media_verified = media["fresh"] == true;
    let second_verified = second["fresh"] == true;

    let restic_known = boolish(&restic["known"]) && !restic["count"].is_null();
    let restic_count = if restic_known {
        number(&restic["count"])
    } else {
        0
    };
    let timeshift_known = boolish(&timeshift["known"]) && !timeshift["count"].is_null();
    let timeshift_count = if timeshift_known {
        number(&timeshift["count"])
    } else {
        0
    };
    let restic_failure = matches!(
        restic["current_state"].as_str(),
        Some("failed" | "missing-credential" | "missing-repository" | "blocked-identity")
    );
    let restic_ready =
        restic_known && restic_count > 0 && !restic_failure && restic["fresh"] == true;
    let timeshift_ready = timeshift_known && timeshift_count > 0 && timeshift["fresh"] == true;
    let check_state = restic["check"].clone();
    let restore_state = restic["restore_test"].clone();
    let restore_ready = restore_state["ok"] == true && restore_state["fresh"] == true;
    let restic_detail = if !string(&restic["current_error"]).is_empty() {
        string(&restic["current_error"])
    } else if restic_known {
        format!(
            "{restic_count} matching snapshot(s) · host {expected_host} · {}",
            nonempty(&restic["freshness"], "unknown")
        )
    } else {
        "Machine-scoped snapshot inventory has not been verified yet.".into()
    };
    let core_checks = vec![
        check(
            "restic",
            "Encrypted Restic repository",
            restic_ready,
            if restic_failure {
                "failed"
            } else if restic_known && restic_count > 0 && restic["freshness"] == "stale" {
                "stale"
            } else if restic_ready {
                "ready"
            } else if restic_known {
                "missing"
            } else {
                "unknown"
            },
            &restic_detail,
            boolish(&restic["cached"]),
        ),
        check(
            "restore-test",
            "Actual restore test",
            restore_ready,
            if restore_state["known"] == true && restore_state["ok"] == false {
                "failed"
            } else if restore_state["ok"] == true && restore_state["fresh"] != true {
                "stale"
            } else if restore_ready {
                "ready"
            } else {
                "untested"
            },
            if restore_ready {
                "A file was restored and matched byte-for-byte."
            } else if restore_state["ok"] == true {
                "Restore verification is stale."
            } else {
                "Run Verify restore while the backup HDD is mounted."
            },
            false,
        ),
        check(
            "timeshift",
            "Timeshift restore points",
            timeshift_ready,
            if timeshift_known && timeshift_count > 0 && timeshift["freshness"] == "stale" {
                "stale"
            } else if timeshift_ready {
                "ready"
            } else if timeshift_known {
                "missing"
            } else {
                "unknown"
            },
            &if timeshift_known {
                format!(
                    "{timeshift_count} restore point(s) verified · {}",
                    nonempty(&timeshift["freshness"], "unknown")
                )
            } else {
                "Restore-point inventory has not been verified yet.".into()
            },
            boolish(&timeshift["cached"]),
        ),
        check(
            "guide",
            "Recovery documentation",
            guide_known,
            if guide_known {
                "ready"
            } else if disk["filesystem_accessible"] == true {
                "missing"
            } else {
                "unknown"
            },
            if guide_known {
                "RESTORE.md is available."
            } else {
                "Mount the backup HDD to verify RESTORE.md."
            },
            disk["filesystem_accessible"] != true && guide_known,
        ),
        check(
            "manifests",
            "Arch system manifests",
            manifests_fresh,
            if manifests_known && !manifests_fresh {
                "stale"
            } else if manifests_fresh {
                "ready"
            } else if disk["filesystem_accessible"] == true {
                "missing"
            } else {
                "unknown"
            },
            &if manifests_fresh {
                "Package and system-state manifests are current.".into()
            } else if manifests_known && !manifests_age.is_null() {
                format!(
                    "Recovery manifests are {:.1} hours old.",
                    manifests_age.as_f64().unwrap_or(0.0)
                )
            } else {
                "Mount the backup HDD to verify recovery manifests.".into()
            },
            disk["filesystem_accessible"] != true && manifests_known,
        ),
        check(
            "credential-recovery",
            "Restic recovery credential",
            credential_verified,
            if credential_verified {
                "ready"
            } else if credential["known"] == true {
                "stale"
            } else {
                "pending"
            },
            &if credential_verified {
                format!(
                    "External credential recovery verified · {}.",
                    nonempty(&credential["label"], "external recovery method")
                )
            } else if credential["known"] == true {
                format!(
                    "Credential recovery proof is {} hours old.",
                    string(&credential["age_hours"])
                )
            } else {
                "Not verified. The Restic password must survive loss of the primary system disk."
                    .into()
            },
            false,
        ),
        check(
            "recovery-media",
            "Bootable recovery media",
            media_verified,
            if media_verified {
                "ready"
            } else if media["known"] == true {
                "stale"
            } else {
                "pending"
            },
            &if media_verified {
                format!(
                    "Bootable recovery media verified · {}.",
                    nonempty(&media["label"], "recovery media")
                )
            } else if media["known"] == true {
                format!(
                    "Recovery-media proof is {} hours old.",
                    string(&media["age_hours"])
                )
            } else {
                "Not verified yet. A stored ISO alone is not counted as bootable recovery media."
                    .into()
            },
            false,
        ),
    ];
    let core_ready = core_checks.iter().filter(|item| item["ok"] == true).count();
    let data_state = restic["data_check"].clone();
    let data_ok = boolish(&data_state["known"])
        && data_state["ok"] == true
        && data_state["identity_valid"] != false;
    let subset = boolish(&data_state["subset"]);
    let total = boolish(&data_state["total_subsets"]);
    let resilience = vec![
        check(
            "second-copy",
            "Second independent copy",
            second_verified,
            if second_verified {
                "ready"
            } else if second["known"] == true {
                "stale"
            } else {
                "recommended"
            },
            &if second_verified {
                format!(
                    "Independent copy verified · {}.",
                    nonempty(&second["label"], "second copy")
                )
            } else if second["known"] == true {
                format!(
                    "Second-copy proof is {} hours old.",
                    string(&second["age_hours"])
                )
            } else {
                "Recommended for protection against failure, theft, or loss of the primary backup HDD.".into()
            },
            false,
        ),
        check(
            "repository-data",
            "Repository data-pack verification",
            data_ok,
            if data_ok {
                "ready"
            } else if data_state["known"] == true && data_state["ok"] == false {
                "failed"
            } else {
                "recommended"
            },
            &if data_ok && subset && total {
                format!(
                    "Data subset {}/{} verified; next subset {}/{}.",
                    string(&data_state["subset"]),
                    string(&data_state["total_subsets"]),
                    string(&data_state["next_subset"]),
                    string(&data_state["total_subsets"])
                )
            } else if data_state["known"] == true {
                nonempty(
                    &data_state["detail"],
                    "Run Check repository to rotate through stored data packs.",
                )
            } else {
                "Run Check repository to verify structure and rotate through stored data packs."
                    .into()
            },
            false,
        ),
    ];
    let mut alerts = Vec::new();
    if disk["mounted"] == true && disk["mounted_identity_verified"] != true {
        let actual = nonempty(&disk["mounted_uuid"], "unavailable");
        alerts.push(attention("critical", "IDENTITY", "Unverified filesystem at backup mountpoint",
            &format!("Expected backup UUID {uuid}, but the mounted filesystem UUID is {actual}. Backup/recovery reads and writes are blocked.")));
    }
    match restic["current_state"].as_str() {
        Some("missing-credential") => alerts.push(attention("critical", "CREDENTIAL", "Restic password file is missing",
            "The repository cannot be opened until the configured Restic password file is restored.")),
        Some("missing-repository") => alerts.push(attention("critical", "REPOSITORY", "Restic repository is missing",
            "The verified backup filesystem is mounted, but the configured Restic repository directory is missing.")),
        Some("failed") => alerts.push(attention("critical", "ERROR", "Restic repository query failed",
            &nonempty(&restic["current_error"], "Restic could not verify the configured repository.").chars().take(260).collect::<String>())),
        _ => {}
    }
    if restic_age.as_f64().is_some_and(|age| age > overdue as f64) {
        alerts.push(attention(
            "warning",
            "DUE",
            "Backup overdue",
            &format!(
                "Last known Restic snapshot is {:.1} hours old.",
                restic_age.as_f64().unwrap_or(0.0)
            ),
        ));
    }
    if ts_age
        .as_f64()
        .is_some_and(|age| age > timeshift_overdue as f64)
    {
        alerts.push(attention("warning", "DUE", "Restore point overdue",
            &format!("Latest Timeshift restore point is {:.1} hours old; target is {timeshift_overdue} hours.", ts_age.as_f64().unwrap_or(0.0))));
    }
    if manifests_known && !manifests_fresh {
        alerts.push(attention("warning", "DUE", "Recovery manifests are stale",
            &format!("Recovery manifests are {:.1} hours old; refresh them when the backup disk is mounted.", manifests_age.as_f64().unwrap_or(0.0))));
    }
    if check_state["known"] == true && check_state["ok"] == false {
        alerts.push(attention(
            "critical",
            "VERIFY",
            "Repository integrity check failed",
            &nonempty(
                &check_state["detail"],
                "The most recent repository check failed.",
            )
            .chars()
            .take(260)
            .collect::<String>(),
        ));
    } else if check_state["provenance_state"] == "identity-mismatch" {
        alerts.push(attention(
            "unverified",
            "IDENTITY",
            "Repository-check proof belongs to different backup identity",
            "Run Check repository against the currently configured repository.",
        ));
    } else if check_state["provenance_state"] == "superseded" {
        alerts.push(attention("unverified", "VERIFY", "Repository check predates the latest snapshot",
            "A newer matching snapshot exists than the snapshot covered by the last repository verification."));
    } else if check_state["ok"] == true && check_state["fresh"] != true {
        alerts.push(attention(
            "unverified",
            "DUE",
            "Repository check is stale",
            &format!(
                "The last repository check is {} hours old.",
                py_string(&check_state["age_hours"])
            ),
        ));
    }
    if restore_state["known"] == true && restore_state["ok"] == false {
        alerts.push(attention(
            "critical",
            "RESTORE",
            "Restore verification failed",
            &nonempty(
                &restore_state["detail"],
                "The most recent real restore verification failed.",
            )
            .chars()
            .take(260)
            .collect::<String>(),
        ));
    } else if restore_state["provenance_state"] == "identity-mismatch" {
        alerts.push(attention(
            "unverified",
            "IDENTITY",
            "Restore proof belongs to different backup identity",
            "Run Verify restore against the currently configured backup repository.",
        ));
    } else if restore_state["provenance_state"] == "superseded" {
        alerts.push(attention("unverified", "VERIFY", "Latest snapshot has not been restore-tested",
            "A newer matching snapshot exists than the one covered by the last real restore verification."));
    } else if restore_state["ok"] == true && restore_state["fresh"] != true {
        alerts.push(attention(
            "unverified",
            "DUE",
            "Restore verification is stale",
            &format!(
                "The last real restore verification is {} hours old.",
                py_string(&restore_state["age_hours"])
            ),
        ));
    }
    if restic_known && restic_count > 0 && restic["backup_proof"]["current"] != true {
        alerts.push(attention("unverified", "PROOF", "Latest snapshot lacks Backup Recovery action proof",
            "The latest matching snapshot exists, but it was not yet linked to a successful post-backup verification marker from this action engine."));
    }
    if credential["known"] == true && !credential_verified {
        alerts.push(attention("unverified", "DUE", "Recovery credential proof is stale",
            "Re-confirm that the Restic recovery credential still exists outside the primary system disk."));
    } else if credential["known"] != true {
        alerts.push(attention("unverified", "CREDENTIAL", "Recovery credential survivability is unverified",
            "The encrypted repository may be unusable after primary-disk loss unless the Restic credential is stored independently."));
    }
    if media["known"] == true && !media_verified {
        alerts.push(attention(
            "unverified",
            "DUE",
            "Bootable recovery-media proof is stale",
            "Re-verify that the recovery medium still boots and is available.",
        ));
    }
    if disk["connected"] == true && disk["mounted"] != true {
        alerts.push(attention(
            "info",
            "INFO",
            "Backup HDD connected but not mounted",
            "Mount it when you want to create or verify backups.",
        ));
    } else if disk["connected"] != true && restic_age.is_null() {
        alerts.push(attention(
            "info",
            "INFO",
            "Backup HDD offline",
            "Offline is normal, but no verified backup age is currently available.",
        ));
    }
    if smart["known"] == true {
        let attrs = &smart["attributes"];
        if ["reallocated", "pending", "uncorrectable"]
            .iter()
            .any(|key| number(&attrs[*key]) > 0)
        {
            alerts.push(attention(
                "critical",
                "RISK",
                "Active SMART sector problem",
                "Reallocated, pending or uncorrectable sector counters are non-zero.",
            ));
        } else if smart["condition"] == "unverified" {
            alerts.push(attention(
                "unverified",
                "UNVERIFIED",
                "SMART health is not verified",
                "SMART data was readable, but no definitive overall-health result was detected.",
            ));
        } else if number(&smart["historical_error_count"]) > 0 {
            alerts.push(attention("history", "HISTORY", "Historical ATA errors",
                &format!("ATA log contains {} historical error(s); current bad-sector counters are zero.", number(&smart["historical_error_count"]))));
        }
    }
    if !smart_error.is_empty() && hardware["connected"] == true {
        alerts.push(attention(
            "unverified",
            "UNVERIFIED",
            "SMART status could not be refreshed",
            &smart_error.chars().take(260).collect::<String>(),
        ));
    }
    if disk["filesystem_accessible"] == true && restic["check"]["known"] != true {
        alerts.push(attention(
            "unverified",
            "UNVERIFIED",
            "Repository integrity has not been checked here",
            "Run Check repository when convenient.",
        ));
    }
    let critical = alerts.iter().any(|item| item["severity"] == "critical");
    let overall = overall(
        critical,
        restic_ready,
        restic_known && restic_count > 0 && restic["freshness"] == "stale",
        timeshift_ready,
        timeshift_known && timeshift_count > 0 && timeshift["freshness"] == "stale",
        &disk,
    );

    let recovery = json!({
        "core_ready": core_ready, "core_total": core_checks.len(), "core_checks": core_checks,
        "ready": core_ready, "total": core_checks.len(), "checks": core_checks,
        "resilience_checks": resilience,
        "restore_doc": restore_doc, "restore_doc_known": guide_known,
        "manifests_path": arch_state, "manifests_known": manifests_known,
        "manifests_updated_at": manifests_timestamp, "manifests_age_hours": manifests_age,
        "manifests_overdue_hours": manifests_overdue, "manifests_freshness": manifests_freshness,
        "manifests_fresh": manifests_fresh, "iso_files": iso_files,
        "credential_evidence": credential, "recovery_media_evidence": media, "second_copy_evidence": second,
        "recovery_media_verified": media_verified, "credential_recovery_verified": credential_verified,
        "second_copy_verified": second_verified,
    });
    let installed = read_json(&paths.at("/etc/backup-recovery/install.json"), json!({}));
    let source_repo = &installed["source_repo"];
    let ci = &installed["ci"];
    let deployment = json!({
        "version": string(&installed["version"]),
        "ui_contract": string(&installed["ui_contract"]),
        "backend_revision": string(&installed["backend_revision"]),
        "state_schema": installed["state_schema"],
        "installed_at": number(&installed["installed_at"]),
        "source": string(&installed["source"]), "phase": string(&installed["phase"]),
        "release_stage": string(&installed["release_stage"]),
        "local_closure": boolish(&installed["local_closure"]),
        "source_repo_detected": boolish(&source_repo["detected"]),
        "source_commit": string(&source_repo["commit"]),
        "source_dirty": boolish(&source_repo["dirty"]),
        "source_verified": boolish(&source_repo["verified"]),
        "ci_verified": boolish(&ci["verified"]),
        "integrity_file_count": installed["files"].as_object().map_or(0, |map| map.len()),
    });
    let state = json!({
        "schema_version": SCHEMA_VERSION, "ui_contract": UI_CONTRACT,
        "backend_revision": BACKEND_REVISION, "deployment": deployment,
        "generated_at": now(), "overall": overall, "disk": disk,
        "restic": restic, "timeshift": timeshift, "smart": smart,
        "history": {"etc": etc_history(paths)}, "recovery": recovery,
        "attention": alerts, "activity": activity(paths), "state_timer": state_timer,
    });
    Ok((state, evidence))
}

fn py_string(value: &Value) -> String {
    if value.is_null() {
        "None".into()
    } else {
        string(value)
    }
}

pub fn collect_state(paths: &Paths, dry_run: bool) -> Result<Value, String> {
    let _lock = if dry_run {
        None
    } else {
        Some(Lock::acquire(
            &paths.at("/run/backup-recovery/state-collector.lock"),
            false,
        )?)
    };
    let (state, evidence) = collect(paths)?;
    if !dry_run {
        atomic_json(&paths.state("evidence.json"), &evidence, 0o640)?;
        atomic_json(&paths.state("state.json"), &state, 0o640)?;
        let user = string(&read_json(&paths.config(), json!({}))["user"]);
        let (_, gid, _) = user_ids(user.trim())?;
        chown_root_group(&paths.state("state.json"), gid, 0o640)?;
    }
    Ok(state)
}
