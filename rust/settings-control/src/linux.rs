use regex::Regex;
use serde_json::{Value, json};
use std::{
    env,
    ffi::CString,
    fs,
    io::Read,
    os::unix::{ffi::OsStrExt, fs::MetadataExt},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant, SystemTime},
};

use crate::state::Paths;

#[derive(Debug)]
pub struct CommandResult {
    pub code: i32,
    pub stdout: String,
    pub stderr: String,
}

pub fn find_executable(name: &str) -> Option<PathBuf> {
    let candidate = Path::new(name);
    if candidate.components().count() > 1 {
        return executable(candidate).then(|| candidate.to_path_buf());
    }
    if let Some(path) = env::var_os("PATH") {
        for directory in env::split_paths(&path) {
            let path = directory.join(name);
            if executable(&path) {
                return Some(path);
            }
        }
    }
    let home = PathBuf::from(env::var_os("HOME").unwrap_or_else(|| "/".into()));
    [
        PathBuf::from("/usr/bin"),
        PathBuf::from("/usr/local/bin"),
        home.join(".local/bin"),
    ]
    .into_iter()
    .map(|directory| directory.join(name))
    .find(|path| executable(path))
}

fn executable(path: &Path) -> bool {
    if !fs::metadata(path).is_ok_and(|metadata| metadata.is_file()) {
        return false;
    }
    let Ok(encoded) = CString::new(path.as_os_str().as_bytes()) else {
        return false;
    };
    unsafe { libc::access(encoded.as_ptr(), libc::X_OK) == 0 }
}

pub fn run_command(
    binary: &Path,
    args: &[&str],
    timeout: Duration,
    signature: Option<&str>,
) -> CommandResult {
    let mut command = Command::new(binary);
    command
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    if let Some(signature) = signature {
        command.env("HYPRLAND_INSTANCE_SIGNATURE", signature);
    }
    let mut child = match command.spawn() {
        Ok(child) => child,
        Err(error) => {
            return CommandResult {
                code: 127,
                stdout: String::new(),
                stderr: error.to_string(),
            };
        }
    };
    let stdout = child.stdout.take().expect("piped stdout");
    let stderr = child.stderr.take().expect("piped stderr");
    let out_thread = thread::spawn(move || read_bounded(stdout));
    let err_thread = thread::spawn(move || read_bounded(stderr));
    let deadline = Instant::now() + timeout;
    let code = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status.code().unwrap_or(127),
            Ok(None) if Instant::now() < deadline => thread::sleep(Duration::from_millis(10)),
            Ok(None) => {
                let _ = child.kill();
                let _ = child.wait();
                break 127;
            }
            Err(_) => {
                let _ = child.kill();
                let _ = child.wait();
                break 127;
            }
        }
    };
    let stdout = out_thread.join().unwrap_or_default();
    let stderr = err_thread.join().unwrap_or_default();
    CommandResult {
        code,
        stdout,
        stderr,
    }
}

fn read_bounded(mut reader: impl Read) -> String {
    let mut bytes = Vec::new();
    let _ = reader.by_ref().take(1024 * 1024).read_to_end(&mut bytes);
    String::from_utf8_lossy(&bytes).into_owned()
}

fn hyprland_signatures() -> Vec<Option<String>> {
    let active = env::var("HYPRLAND_INSTANCE_SIGNATURE").unwrap_or_default();
    let mut candidates = vec![None];
    let runtime = env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(format!("/run/user/{}", unsafe { libc::getuid() })));
    let mut entries: Vec<(SystemTime, String)> = fs::read_dir(runtime.join("hypr"))
        .ok()
        .into_iter()
        .flatten()
        .flatten()
        .filter(|entry| entry.path().is_dir())
        .filter_map(|entry| {
            Some((
                entry.metadata().ok()?.modified().ok()?,
                entry.file_name().to_string_lossy().into_owned(),
            ))
        })
        .collect();
    entries.sort_by_key(|entry| std::cmp::Reverse(entry.0));
    for (_, signature) in entries.into_iter().take(8) {
        if signature != active {
            candidates.push(Some(signature));
        }
    }
    candidates
}

pub fn run_hyprctl(args: &[&str]) -> CommandResult {
    let Some(binary) = find_executable("hyprctl") else {
        return CommandResult {
            code: 127,
            stdout: String::new(),
            stderr: "hyprctl not found".into(),
        };
    };
    let mut last = CommandResult {
        code: 127,
        stdout: String::new(),
        stderr: "Hyprland unavailable".into(),
    };
    for signature in hyprland_signatures() {
        let result = run_command(&binary, args, Duration::from_secs(4), signature.as_deref());
        if result.code == 0 {
            return result;
        }
        last = result;
    }
    last
}

pub fn shell_process_info() -> Value {
    let mut shell_pids = Vec::new();
    let mut settings_pids = Vec::new();
    let uid = unsafe { libc::getuid() };
    let Ok(entries) = fs::read_dir("/proc") else {
        return json!({"shell_running": false, "shell_pids": [], "settings_running": false, "settings_pids": []});
    };
    for entry in entries.flatten() {
        let Some(pid) = entry
            .file_name()
            .to_str()
            .and_then(|name| name.parse::<u32>().ok())
        else {
            continue;
        };
        if entry.metadata().ok().map(|metadata| metadata.uid()) != Some(uid) {
            continue;
        }
        let Ok(bytes) = fs::read(entry.path().join("cmdline")) else {
            continue;
        };
        let args: Vec<String> = bytes
            .split(|byte| *byte == 0)
            .filter(|arg| !arg.is_empty())
            .map(|arg| String::from_utf8_lossy(arg).into_owned())
            .collect();
        let Some(executable) = args
            .first()
            .and_then(|arg| Path::new(arg).file_name())
            .and_then(|name| name.to_str())
        else {
            continue;
        };
        if executable != "qs" && executable != "quickshell" {
            continue;
        }
        for pair in args.windows(2) {
            if pair[0] == "-c" && (pair[1] == "nyvorel" || pair[1] == "ii") {
                shell_pids.push(pid);
            }
            if pair[0] == "-p" && pair[1].ends_with("settings.qml") {
                settings_pids.push(pid);
            }
        }
    }
    shell_pids.sort_unstable();
    settings_pids.sort_unstable();
    json!({
        "shell_running": !shell_pids.is_empty(),
        "shell_pids": shell_pids,
        "settings_running": !settings_pids.is_empty(),
        "settings_pids": settings_pids,
    })
}

pub fn hyprland_health(paths: &Paths) -> Value {
    let version_result = run_hyprctl(&["version"]);
    let hyprland_ok = version_result.code == 0;
    let version_raw = if version_result.stdout.trim().is_empty() {
        &version_result.stderr
    } else {
        &version_result.stdout
    };
    let version = Regex::new(r"\bHyprland\s+([0-9]+\.[0-9]+(?:\.[0-9]+)?)")
        .ok()
        .and_then(|pattern| pattern.captures(version_raw))
        .and_then(|captures| captures.get(1).map(|part| part.as_str().to_owned()))
        .unwrap_or_default();
    let errors_result = run_hyprctl(&["configerrors"]);
    let errors_available = errors_result.code == 0;
    let errors: Vec<String> = if errors_available {
        errors_result
            .stdout
            .lines()
            .map(str::trim)
            .filter(|line| !line.is_empty())
            .map(str::to_owned)
            .collect()
    } else {
        Vec::new()
    };
    let config_path = env::var("HYPRLAND_CONFIG")
        .ok()
        .filter(|path| !path.trim().is_empty())
        .map(|path| expand_path(&path))
        .unwrap_or_else(|| {
            let lua = paths.xdg_config.join("hypr/hyprland.lua");
            if lua.is_file() {
                lua
            } else {
                paths.xdg_config.join("hypr/hyprland.conf")
            }
        });
    let legacy_conf = config_path.exists()
        && config_path
            .extension()
            .is_some_and(|extension| extension.eq_ignore_ascii_case("conf"));
    let warnings = if legacy_conf {
        vec![json!({
            "code": "hyprland-conf-deprecated",
            "title": "Legacy Hyprland .conf configuration",
            "detail": "The current .conf format is deprecated and is scheduled for removal in Hyprland 0.57.",
            "path": config_path.to_string_lossy()
        })]
    } else {
        Vec::new()
    };
    json!({
        "hyprland_ok": hyprland_ok,
        "hyprland_version": version,
        "hyprland_config_errors_available": errors_available,
        "hyprland_config_errors": errors,
        "hyprland_config_error_count": errors.len(),
        "hyprland_config_path": config_path.to_string_lossy(),
        "hyprland_legacy_conf": legacy_conf,
        "warnings": warnings,
    })
}

fn expand_path(input: &str) -> PathBuf {
    let mut text = input.to_owned();
    if text == "~" || text.starts_with("~/") {
        let home = env::var("HOME").unwrap_or_default();
        text = format!("{home}{}", &text[1..]);
    }
    let variables = Regex::new(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)")
        .expect("valid regex");
    let expanded = variables.replace_all(&text, |caps: &regex::Captures<'_>| {
        env::var(
            caps.get(1)
                .or_else(|| caps.get(2))
                .expect("variable capture")
                .as_str(),
        )
        .unwrap_or_default()
    });
    PathBuf::from(expanded.into_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn subprocess_timeout_is_bounded() {
        let start = Instant::now();
        let result = run_command(
            Path::new("/usr/bin/sleep"),
            &["2"],
            Duration::from_millis(25),
            None,
        );
        assert_ne!(result.code, 0);
        assert!(start.elapsed() < Duration::from_secs(1));
    }
}
