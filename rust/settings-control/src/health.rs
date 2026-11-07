use serde_json::{Value, json};

use crate::{linux, state};

pub fn summary(paths: &state::Paths, stored: &Value) -> Value {
    let (config_valid, config_error) = match state::read_config(paths) {
        Ok(_) => (true, String::new()),
        Err(error) => (false, error),
    };
    let processes = linux::shell_process_info();
    let hyprland = linux::hyprland_health(paths);
    let mut critical = Vec::new();
    if !config_valid {
        critical.push(json!({"code": "config-invalid", "title": "config.json is invalid", "detail": config_error}));
    }
    if hyprland["hyprland_ok"] != true {
        critical.push(json!({"code": "hyprland-unavailable", "title": "Hyprland integration unavailable", "detail": "hyprctl could not contact the active Hyprland session."}));
    }
    if processes["shell_running"] != true {
        critical.push(json!({"code": "quickshell-main-missing", "title": "Main Quickshell instance not detected", "detail": "Expected qs/quickshell -c nyvorel."}));
    }
    let error_count = hyprland["hyprland_config_error_count"]
        .as_u64()
        .unwrap_or(0);
    if hyprland["hyprland_config_errors_available"] == true && error_count > 0 {
        let detail = hyprland["hyprland_config_errors"]
            .as_array()
            .map(|items| {
                items
                    .iter()
                    .take(8)
                    .filter_map(Value::as_str)
                    .collect::<Vec<_>>()
                    .join("\n")
            })
            .unwrap_or_default();
        critical.push(json!({"code": "hyprland-config-errors", "title": "Hyprland reports configuration errors", "detail": detail}));
    }
    let warning_count = hyprland["warnings"].as_array().map_or(0, Vec::len);
    let mut result = json!({
        "config_path": paths.config.to_string_lossy(),
        "state_path": paths.state.to_string_lossy(),
        "last_backup": stored["last_backup"],
        "favorite_count": stored["favorites"].as_array().map_or(0, Vec::len),
        "history_count": state::history_count(stored),
        "can_undo": stored["history"].as_array().is_some_and(|items| !items.is_empty()),
        "config_valid": config_valid,
        "config_error": config_error,
        "critical_issues": critical,
        "critical_count": critical.len(),
        "warning_count": warning_count,
        "diagnostics_ok": critical.is_empty(),
    });
    for component in [&processes, &hyprland] {
        for (key, value) in component.as_object().expect("component is an object") {
            result[key] = value.clone();
        }
    }
    result
}
