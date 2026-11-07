use regex::Regex;
use serde_json::{Map, Value};
use std::collections::BTreeSet;
use std::fs::{self, File};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const ROLES: &[&str] = &[
    "background",
    "error",
    "error_container",
    "inverse_on_surface",
    "inverse_primary",
    "inverse_surface",
    "on_background",
    "on_error",
    "on_error_container",
    "on_primary",
    "on_primary_container",
    "on_primary_fixed",
    "on_primary_fixed_variant",
    "on_secondary",
    "on_secondary_container",
    "on_secondary_fixed",
    "on_secondary_fixed_variant",
    "on_surface",
    "on_surface_variant",
    "on_tertiary",
    "on_tertiary_container",
    "on_tertiary_fixed",
    "on_tertiary_fixed_variant",
    "outline",
    "outline_variant",
    "primary",
    "primary_container",
    "primary_fixed",
    "primary_fixed_dim",
    "scrim",
    "secondary",
    "secondary_container",
    "secondary_fixed",
    "secondary_fixed_dim",
    "shadow",
    "surface",
    "surface_bright",
    "surface_container",
    "surface_container_high",
    "surface_container_highest",
    "surface_container_low",
    "surface_container_lowest",
    "surface_dim",
    "surface_tint",
    "surface_variant",
    "tertiary",
    "tertiary_container",
    "tertiary_fixed",
    "tertiary_fixed_dim",
];
const REQUIRED: &[&str] = &[
    "background",
    "on_background",
    "surface",
    "on_surface",
    "primary",
    "on_primary",
    "primary_container",
    "on_primary_container",
    "secondary",
    "secondary_container",
    "tertiary",
    "tertiary_container",
    "outline",
    "outline_variant",
];

fn snake_role(name: &str) -> String {
    let mut result = String::new();
    for (index, character) in name.replace('-', "_").chars().enumerate() {
        if character.is_uppercase() && index != 0 {
            result.push('_');
        }
        result.extend(character.to_lowercase());
    }
    result
}

fn palette_candidate(value: &Value, mode: &str) -> Map<String, Value> {
    let mut result = Map::new();
    let Some(object) = value.as_object() else {
        return result;
    };
    let color = Regex::new(r"(?i)^#?([0-9a-f]{6})(?:[0-9a-f]{2})?$").unwrap();
    for (key, value) in object {
        let role = snake_role(key);
        if !ROLES.contains(&role.as_str()) {
            continue;
        }
        let Some(raw) = value
            .as_str()
            .or_else(|| {
                value
                    .get(mode)
                    .and_then(|entry| entry.get("color"))
                    .and_then(Value::as_str)
            })
            .or_else(|| {
                value
                    .get("default")
                    .and_then(|entry| entry.get("color"))
                    .and_then(Value::as_str)
            })
        else {
            continue;
        };
        let Some(capture) = color.captures(raw.trim()) else {
            continue;
        };
        result.insert(
            role,
            Value::String(format!("#{}", capture[1].to_lowercase())),
        );
    }
    result
}

fn collect_candidates(value: &Value, mode: &str, hint: &str, rows: &mut Vec<Map<String, Value>>) {
    if let Some(object) = value.as_object() {
        let candidate = palette_candidate(value, mode);
        if !candidate.is_empty() {
            if hint.eq_ignore_ascii_case(mode) {
                rows.insert(0, candidate);
            } else {
                rows.push(candidate);
            }
        }
        for (key, child) in object {
            collect_candidates(child, mode, key, rows);
        }
    } else if let Some(array) = value.as_array() {
        for child in array {
            collect_candidates(child, mode, hint, rows);
        }
    }
}

pub fn extract(data: &Value, mode: &str) -> Result<Value, String> {
    let mut rows = Vec::new();
    collect_candidates(data, mode, "", &mut rows);
    let required: BTreeSet<&str> = REQUIRED.iter().copied().collect();
    let best = rows
        .into_iter()
        .max_by_key(|row| {
            let complete = REQUIRED.iter().all(|role| row.contains_key(*role));
            (complete, row.len())
        })
        .ok_or("Matugen JSON did not contain a Material role map")?;
    let missing: Vec<&str> = required
        .into_iter()
        .filter(|role| !best.contains_key(*role))
        .collect();
    if !missing.is_empty() {
        return Err(format!(
            "Matugen palette is incomplete; missing {}",
            missing.join(", ")
        ));
    }
    Ok(Value::Object(best))
}

struct Scratch(PathBuf);
impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

pub fn generate(seed: &str, scheme: &str, mode: &str) -> Result<Value, String> {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| error.to_string())?
        .as_nanos();
    let scratch = Scratch(std::env::temp_dir().join(format!(
        "nyvorel-appearance-matugen-{}-{nonce}",
        std::process::id()
    )));
    let config = scratch.0.join("matugen");
    fs::create_dir_all(&config).map_err(|error| error.to_string())?;
    fs::write(
        config.join("config.toml"),
        "[config]\nversion_check = false\n[templates]\n",
    )
    .map_err(|error| error.to_string())?;
    let stdout_path = scratch.0.join("stdout.json");
    let stderr_path = scratch.0.join("stderr.txt");
    let stdout_file = File::create(&stdout_path).map_err(|error| error.to_string())?;
    let stderr_file = File::create(&stderr_path).map_err(|error| error.to_string())?;
    let mut child = Command::new("matugen")
        .args([
            "color", "hex", seed, "--mode", mode, "--type", scheme, "--json", "hex",
        ])
        .env("XDG_CONFIG_HOME", &scratch.0)
        .stdin(Stdio::null())
        .stdout(Stdio::from(stdout_file))
        .stderr(Stdio::from(stderr_file))
        .spawn()
        .map_err(|error| error.to_string())?;
    let deadline = Instant::now() + Duration::from_secs(25);
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(20)),
            Ok(None) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err("Matugen palette generation timed out after 25 seconds".into());
            }
            Err(error) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(format!("Could not wait for Matugen: {error}"));
            }
        }
    };
    let stdout = fs::read(&stdout_path).map_err(|error| error.to_string())?;
    let stderr = fs::read(&stderr_path).map_err(|error| error.to_string())?;
    if stdout.len() > 4 * 1024 * 1024 || stderr.len() > 4 * 1024 * 1024 {
        return Err("Matugen palette output exceeded the size limit".into());
    }
    if !status.success() {
        let detail = if stderr.is_empty() { &stdout } else { &stderr };
        return Err(String::from_utf8_lossy(detail)
            .trim()
            .chars()
            .rev()
            .take(1200)
            .collect::<String>()
            .chars()
            .rev()
            .collect());
    }
    let raw = String::from_utf8_lossy(&stdout);
    let data = serde_json::from_str::<Value>(raw.trim()).or_else(|_| {
        let start = raw
            .find('{')
            .ok_or("Matugen --json returned invalid JSON")?;
        let end = raw
            .rfind('}')
            .ok_or("Matugen --json returned invalid JSON")?;
        serde_json::from_str(&raw[start..=end]).map_err(|_| "Matugen --json returned invalid JSON")
    })?;
    extract(&data, mode)
}

#[cfg(test)]
mod tests {
    use super::{extract, REQUIRED};
    use serde_json::{json, Map, Value};

    #[test]
    fn nested_matugen_roles_use_requested_mode_and_require_complete_map() {
        let mut colors = Map::new();
        for role in REQUIRED {
            colors.insert(
                (*role).into(),
                json!({
                    "dark": {"color": "#AABBCC"},
                    "light": {"color": "#112233"}
                }),
            );
        }
        let data = json!({"colors": Value::Object(colors.clone())});
        let light = extract(&data, "light").unwrap();
        assert_eq!(light["primary"], "#112233");
        colors.remove("primary");
        let error = extract(&json!({"colors": colors}), "dark").unwrap_err();
        assert!(error.contains("primary"));
    }
}
