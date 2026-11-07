//! Persist the Settings window radius in Hyprland's active config format.
//! This command is invoked only when the user changes the radius control.

use regex::Regex;
use std::{
    env, fs,
    fs::OpenOptions,
    io::Write,
    os::{fd::AsRawFd, unix::fs::PermissionsExt},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

const LUA_BEGIN: &str = "-- >>> Appearance Studio: window radius >>>";
const LUA_END: &str = "-- <<< Appearance Studio: window radius <<<";
const CONF_BEGIN: &str = "# >>> appearance-studio-window-radius >>>";
const CONF_END: &str = "# <<< appearance-studio-window-radius <<<";

fn xdg(name: &str, fallback: &str) -> Result<PathBuf, String> {
    if let Some(value) = env::var_os(name).filter(|value| !value.is_empty()) {
        return Ok(PathBuf::from(value));
    }
    let home = env::var_os("HOME").ok_or("HOME is unset")?;
    Ok(PathBuf::from(home).join(fallback))
}

fn clamp(raw: &str) -> Result<i32, String> {
    let value = raw
        .parse::<f64>()
        .map_err(|_| format!("Invalid radius: {raw}"))?;
    if !value.is_finite() {
        return Err(format!("Invalid radius: {raw}"));
    }
    Ok(value.round_ties_even().clamp(0.0, 40.0) as i32)
}

fn managed_pattern(begin: &str, end: &str) -> Result<Regex, String> {
    Regex::new(&format!(
        "(?s){}.*?{}\\n?",
        regex::escape(begin),
        regex::escape(end)
    ))
    .map_err(|error| error.to_string())
}

fn render_lua(original: &str, value: i32) -> Result<String, String> {
    let block = format!(
        "{LUA_BEGIN}\nhl.config({{[\"decoration\"] = {{[\"rounding\"] = {value}}}}})\n{LUA_END}"
    );
    let pattern = managed_pattern(LUA_BEGIN, LUA_END)?;
    let without = pattern.replace(original, "");
    let trimmed = without.trim_end();
    Ok(if trimmed.is_empty() {
        format!("{block}\n")
    } else {
        format!("{trimmed}\n\n{block}\n")
    })
}

fn render_conf(original: &str, value: i32) -> Result<String, String> {
    let setting =
        Regex::new(r"(?m)^(?P<indent>\s*)rounding\s*=\s*[^#\n]+(?P<comment>\s*(?:#.*)?)$")
            .map_err(|error| error.to_string())?;
    if let Some(found) = setting.captures(original) {
        let whole = found.get(0).unwrap();
        return Ok(format!(
            "{}{}rounding = {}{}{}",
            &original[..whole.start()],
            &found["indent"],
            value,
            &found["comment"],
            &original[whole.end()..]
        ));
    }
    let block = format!("{CONF_BEGIN}\ndecoration {{\n    rounding = {value}\n}}\n{CONF_END}\n");
    let managed = managed_pattern(CONF_BEGIN, CONF_END)?;
    if let Some(found) = managed.find(original) {
        return Ok(format!(
            "{}{}{}",
            &original[..found.start()],
            block,
            &original[found.end()..]
        ));
    }
    let mut output = original.to_owned();
    if !output.is_empty() && !output.ends_with('\n') {
        output.push('\n');
    }
    output.push('\n');
    output.push_str(&block);
    Ok(output)
}

fn atomic_write(path: &Path, contents: &str) -> Result<(), String> {
    if path
        .symlink_metadata()
        .is_ok_and(|meta| meta.file_type().is_symlink())
    {
        return Err(format!("Refusing symlink output: {}", path.display()));
    }
    let parent = path.parent().ok_or("Runtime path has no parent")?;
    fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| error.to_string())?
        .as_nanos();
    let staging = parent.join(format!(
        ".appearance-radius-{}-{nonce}.tmp",
        std::process::id()
    ));
    let mode = path
        .metadata()
        .map(|meta| meta.permissions().mode() & 0o777)
        .unwrap_or(0o644);
    let result = (|| {
        let mut output = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&staging)
            .map_err(|error| error.to_string())?;
        output
            .write_all(contents.as_bytes())
            .map_err(|error| error.to_string())?;
        output.sync_all().map_err(|error| error.to_string())?;
        fs::set_permissions(&staging, fs::Permissions::from_mode(mode))
            .map_err(|error| error.to_string())?;
        fs::rename(&staging, path).map_err(|error| error.to_string())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&staging);
    }
    result
}

fn apply_runtime(value: i32) {
    let Ok(mut child) = Command::new("hyprctl")
        .args(["keyword", "decoration:rounding", &value.to_string()])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
    else {
        return;
    };
    let deadline = Instant::now() + Duration::from_secs(3);
    loop {
        match child.try_wait() {
            Ok(Some(_)) => return,
            Ok(None) if Instant::now() < deadline => thread::sleep(Duration::from_millis(15)),
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                return;
            }
        }
    }
}

pub fn run(args: &[String]) -> Result<(), String> {
    if args.len() != 2 || args[0] != "window" {
        return Err("Usage: __semantic-radius window <0..40>".into());
    }
    let value = clamp(&args[1])?;
    let cache = xdg("XDG_CACHE_HOME", ".cache")?.join("nyvorel-appearance-studio");
    fs::create_dir_all(&cache).map_err(|error| error.to_string())?;
    let lock = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(cache.join("semantic-radius.lock"))
        .map_err(|error| error.to_string())?;
    // SAFETY: lock.as_raw_fd() stays valid while the File is held. flock only
    // changes the advisory lock on that descriptor and has no memory access.
    if unsafe { libc::flock(lock.as_raw_fd(), libc::LOCK_EX) } != 0 {
        return Err(format!(
            "Could not lock radius writer: {}",
            std::io::Error::last_os_error()
        ));
    }
    let config = xdg("XDG_CONFIG_HOME", ".config")?.join("hypr");
    let native = config.join("hyprland.lua").is_file();
    let runtime = config.join("custom").join(if native {
        "appearance-runtime.lua"
    } else {
        "appearance-runtime.conf"
    });
    let original = match fs::read_to_string(&runtime) {
        Ok(text) => text,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => String::new(),
        Err(error) => return Err(format!("Could not read {}: {error}", runtime.display())),
    };
    let updated = if native {
        render_lua(&original, value)?
    } else {
        render_conf(&original, value)?
    };
    atomic_write(&runtime, &updated)?;
    apply_runtime(value);
    Ok(())
}
