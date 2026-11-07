//! Read-only package inventory verification with one bounded hash process.
use crate::process;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Duration;

fn expanded(raw: &str) -> PathBuf {
    if raw == "~" {
        return crate::home();
    }
    if let Some(rest) = raw.strip_prefix("~/") {
        return crate::home().join(rest);
    }
    PathBuf::from(raw)
}

fn hashes(paths: &[PathBuf]) -> Option<HashMap<PathBuf, String>> {
    if paths.is_empty() {
        return Some(HashMap::new());
    }
    let mut command = Command::new("/usr/bin/sha256sum");
    command.args(["--zero", "--"]);
    command.args(paths);
    let output = process::run(&mut command, Duration::from_secs(8)).ok()??;
    if !output.status.success() || !output.stderr.is_empty() {
        return None;
    }
    let mut result = HashMap::new();
    for record in output
        .stdout
        .split('\0')
        .filter(|record| !record.is_empty())
    {
        let (hash, path) = record.split_once("  ")?;
        if hash.len() != 64 || !hash.bytes().all(|byte| byte.is_ascii_hexdigit()) {
            return None;
        }
        result.insert(PathBuf::from(path), hash.to_string());
    }
    (paths.iter().all(|path| result.contains_key(path))).then_some(result)
}

pub fn sha256_file(path: &Path) -> Option<String> {
    hashes(&[path.to_path_buf()])?.remove(path)
}

pub fn run(manifest: &str) -> Value {
    let path = Path::new(manifest);
    let payload = fs::read(path)
        .ok()
        .and_then(|bytes| serde_json::from_slice::<Value>(&bytes).ok());
    let Some(Value::Object(payload)) = payload else {
        return json!({"ok": false, "revision": "missing", "manifest": manifest,
            "files": [], "reason": "Deployment integrity manifest is missing."});
    };
    let revision = payload
        .get("revision")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .unwrap_or("unknown");
    let Some(Value::Array(items)) = payload.get("files") else {
        return json!({"ok": false, "revision": revision, "manifest": manifest,
            "files": [], "reason": "Deployment integrity manifest has no file inventory."});
    };
    if items.is_empty() {
        return json!({"ok": false, "revision": revision, "manifest": manifest,
            "files": [], "reason": "Deployment integrity manifest has no file inventory."});
    }
    let mut existing = Vec::new();
    for item in items {
        let Some(item) = item.as_object() else {
            continue;
        };
        let raw = item.get("path").and_then(Value::as_str).unwrap_or("");
        let path = expanded(raw);
        if path.is_file() {
            existing.push(path);
        }
    }
    let Some(digests) = hashes(&existing) else {
        return json!({"error": true, "message": "Could not hash deployment inventory"});
    };
    let mut results = Vec::new();
    for item in items {
        let Some(item) = item.as_object() else {
            continue;
        };
        let raw = item.get("path").and_then(Value::as_str).unwrap_or("");
        let expected = item.get("sha256").and_then(Value::as_str).unwrap_or("");
        let expected_mode = item.get("mode").and_then(Value::as_str).unwrap_or("");
        let path = expanded(raw);
        let exists = path.is_file();
        let actual = digests.get(&path).cloned().unwrap_or_default();
        let mode = if exists {
            fs::metadata(&path)
                .map(|metadata| format!("{:04o}", metadata.permissions().mode() & 0o7777))
                .unwrap_or_default()
        } else {
            String::new()
        };
        let hash_ok = exists && !expected.is_empty() && actual == expected;
        let mode_ok = expected_mode.is_empty() || mode == expected_mode;
        results.push(json!({"path": path.to_string_lossy(), "exists": exists,
            "hash_ok": hash_ok, "mode_ok": mode_ok, "expected_sha256": expected,
            "actual_sha256": actual, "expected_mode": expected_mode,
            "actual_mode": mode, "error": ""}));
    }
    let ok = !results.is_empty()
        && results
            .iter()
            .all(|row| row["hash_ok"] == true && row["mode_ok"] == true);
    json!({"ok": ok, "revision": revision,
        "generated_at": payload.get("generated_at").unwrap_or(&Value::String(String::new())),
        "manifest": manifest, "files": results,
        "reason": if ok {"All package-owned files match the deployment manifest."}
                  else {"One or more package-owned files drifted from the deployment manifest."}})
}
