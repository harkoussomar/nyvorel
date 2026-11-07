//! One-shot host summary. No resident process or background polling.
use crate::process;
use serde_json::{json, Value};
use std::env;
use std::ffi::CString;
use std::fs;
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Duration;

fn human_bytes(mut value: f64) -> String {
    for suffix in ["B", "KB", "MB", "GB", "TB"] {
        if value < 1024.0 || suffix == "TB" {
            return if suffix == "B" || suffix == "KB" {
                format!("{value:.0} {suffix}")
            } else {
                format!("{value:.1} {suffix}")
            };
        }
        value /= 1024.0;
    }
    "0 B".into()
}

fn human_seconds(seconds: f64) -> String {
    let seconds = seconds.max(0.0) as u64;
    if seconds < 60 {
        return format!("{seconds}s");
    }
    let minutes = seconds / 60;
    if minutes < 60 {
        return format!("{}m {:02}s", minutes, seconds % 60);
    }
    let hours = minutes / 60;
    if hours < 24 {
        return format!("{}h {:02}m", hours, minutes % 60);
    }
    format!("{}d {}h", hours / 24, hours % 24)
}

fn disk(home: &Path) -> Option<(f64, f64, f64)> {
    let path = CString::new(home.as_os_str().as_bytes()).ok()?;
    let mut stats = std::mem::MaybeUninit::<libc::statvfs>::uninit();
    if unsafe { libc::statvfs(path.as_ptr(), stats.as_mut_ptr()) } != 0 {
        return None;
    }
    let stats = unsafe { stats.assume_init() };
    let block = stats.f_frsize as f64;
    let total = stats.f_blocks as f64 * block;
    let used = (stats.f_blocks - stats.f_bfree) as f64 * block;
    let free = stats.f_bavail as f64 * block;
    Some((total, used, free))
}

fn hostname() -> String {
    let mut buffer = [0_u8; 256];
    if unsafe { libc::gethostname(buffer.as_mut_ptr().cast(), buffer.len()) } != 0 {
        return String::new();
    }
    let end = buffer
        .iter()
        .position(|byte| *byte == 0)
        .unwrap_or(buffer.len());
    String::from_utf8_lossy(&buffer[..end]).into_owned()
}

pub fn run() -> Value {
    let home = env::var_os("HOME").map(PathBuf::from).unwrap_or_default();
    let user = env::var("USER")
        .ok()
        .filter(|item| !item.is_empty())
        .unwrap_or_else(|| {
            home.file_name()
                .map(|item| item.to_string_lossy().into_owned())
                .unwrap_or_default()
        });
    let (total, used, free) = disk(&home).unwrap_or((0.0, 0.0, 0.0));
    let percent = if total > 0.0 {
        (used / total * 1000.0).round_ties_even() / 10.0
    } else {
        0.0
    };
    let uptime = fs::read_to_string("/proc/uptime")
        .ok()
        .and_then(|content| content.split_whitespace().next()?.parse::<f64>().ok())
        .unwrap_or(0.0);
    let mut loads = [0_f64; 3];
    let load = if unsafe { libc::getloadavg(loads.as_mut_ptr(), 3) } == 3 {
        format!("{:.2} · {:.2} · {:.2}", loads[0], loads[1], loads[2])
    } else {
        "—".into()
    };
    let mut uname = Command::new("uname");
    uname.arg("-r");
    let kernel = match process::run(&mut uname, Duration::from_secs(2)) {
        Ok(Some(output)) => output.stdout.trim().to_string(),
        _ => String::new(),
    };
    json!({"hostname": hostname(), "user": user, "home": home.to_string_lossy(),
        "kernel": kernel, "uptime": human_seconds(uptime), "load": load,
        "storage": {"percent": percent, "free": human_bytes(free), "total": human_bytes(total)}})
}
