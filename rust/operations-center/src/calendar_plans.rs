use serde_json::{json, Value};
use std::{
    env, fs,
    fs::{File, OpenOptions},
    io::Write,
    os::{fd::AsRawFd, unix::fs::OpenOptionsExt},
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

fn state_path() -> PathBuf {
    if let Some(path) = env::var_os("NYVOREL_CALENDAR_STATE_FILE") {
        return PathBuf::from(path);
    }
    let state_home = env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| crate::home().join(".local/state"));
    state_home.join("nyvorel/calendar/plans.json")
}

fn default_state() -> Value {
    json!({"version": 1, "nextId": 1, "items": []})
}

fn valid_date(value: &str) -> bool {
    let bytes = value.as_bytes();
    if bytes.len() != 10
        || bytes[4] != b'-'
        || bytes[7] != b'-'
        || bytes
            .iter()
            .enumerate()
            .any(|(i, c)| i != 4 && i != 7 && !c.is_ascii_digit())
    {
        return false;
    }
    let year = value[0..4].parse::<u32>().unwrap_or(0);
    let month = value[5..7].parse::<usize>().unwrap_or(0);
    let day = value[8..10].parse::<u32>().unwrap_or(0);
    if year == 0 || !(1..=12).contains(&month) {
        return false;
    }
    let leap = year % 400 == 0 || (year % 4 == 0 && year % 100 != 0);
    let days = [
        31,
        if leap { 29 } else { 28 },
        31,
        30,
        31,
        30,
        31,
        31,
        30,
        31,
        30,
        31,
    ];
    day >= 1 && day <= days[month - 1]
}

fn read_state(path: &Path) -> Result<Value, String> {
    let bytes = match fs::read(path) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(default_state()),
        Err(error) => return Err(format!("Could not read plans: {error}")),
    };
    let state: Value = serde_json::from_slice(&bytes)
        .map_err(|error| format!("Could not parse saved plans: {error}"))?;
    if state["version"].as_u64() != Some(1) || !state["items"].is_array() {
        return Err("Saved plans have an unsupported format".into());
    }
    Ok(state)
}

fn write_state(path: &Path, state: &Value) -> Result<(), String> {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let tmp = path.with_extension(format!("tmp-{}-{nonce}", std::process::id()));
    let result = (|| {
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&tmp)
            .map_err(|error| error.to_string())?;
        file.write_all(&serde_json::to_vec(state).map_err(|error| error.to_string())?)
            .map_err(|error| error.to_string())?;
        file.sync_all().map_err(|error| error.to_string())?;
        fs::rename(&tmp, path).map_err(|error| error.to_string())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&tmp);
    }
    result
}

fn run_at(path: &Path, args: &[String]) -> Result<Value, String> {
    let parent = path.parent().ok_or("Invalid calendar state path")?;
    fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    let lock_path = path.with_extension("lock");
    let lock: File = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .open(lock_path)
        .map_err(|error| error.to_string())?;
    if unsafe { libc::flock(lock.as_raw_fd(), libc::LOCK_EX) } != 0 {
        return Err("Could not lock saved plans".into());
    }
    let mut state = read_state(path)?;
    let mut changed = false;
    match args.first().map(String::as_str) {
        Some("list") if args.len() == 1 => {}
        Some("add") if args.len() == 3 => {
            if !valid_date(&args[1]) {
                return Err("Choose a valid calendar date".into());
            }
            let title = args[2].trim();
            if title.is_empty() || title.chars().count() > 120 || title.contains(['\n', '\r']) {
                return Err("Plan text must be 1 to 120 characters on one line".into());
            }
            let items = state["items"].as_array_mut().ok_or("Invalid saved plans")?;
            if items.len() >= 1000 {
                return Err("Saved plans are full; remove older plans first".into());
            }
            let id = state["nextId"].as_u64().unwrap_or(1);
            state["nextId"] = json!(id.saturating_add(1));
            state["items"]
                .as_array_mut()
                .ok_or("Invalid saved plans")?
                .push(json!({"id": id, "date": args[1], "title": title, "done": false}));
            changed = true;
        }
        Some("toggle") if args.len() == 2 => {
            let id = args[1].parse::<u64>().map_err(|_| "Invalid plan ID")?;
            let item = state["items"]
                .as_array_mut()
                .ok_or("Invalid saved plans")?
                .iter_mut()
                .find(|item| item["id"].as_u64() == Some(id))
                .ok_or("Plan no longer exists")?;
            item["done"] = json!(!item["done"].as_bool().unwrap_or(false));
            changed = true;
        }
        Some("delete") if args.len() == 2 => {
            let id = args[1].parse::<u64>().map_err(|_| "Invalid plan ID")?;
            let items = state["items"].as_array_mut().ok_or("Invalid saved plans")?;
            let count = items.len();
            items.retain(|item| item["id"].as_u64() != Some(id));
            if items.len() == count {
                return Err("Plan no longer exists".into());
            }
            changed = true;
        }
        _ => return Err("Allowed commands: list, add DATE TEXT, toggle ID, delete ID".into()),
    }
    if changed {
        write_state(path, &state)?;
    }
    Ok(state)
}

pub fn run(args: &[String]) -> Result<Value, String> {
    run_at(&state_path(), args)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_invalid_dates() {
        assert!(valid_date("2028-02-29"));
        assert!(!valid_date("2026-02-29"));
        assert!(!valid_date("2026-13-01"));
        assert!(!valid_date("2026-10-00"));
    }

    #[test]
    fn plans_persist_and_toggle_without_losing_other_dates() {
        let path =
            env::temp_dir().join(format!("nyvorel-calendar-test-{}.json", std::process::id()));
        let _ = fs::remove_file(&path);
        let add =
            |date: &str, title: &str| run_at(&path, &["add".into(), date.into(), title.into()]);
        let first = add("2026-10-14", "Visit doctor").unwrap();
        assert_eq!(first["items"][0]["done"], false);
        add("2026-10-15", "Pay bill").unwrap();
        run_at(&path, &["toggle".into(), "1".into()]).unwrap();
        let saved = run_at(&path, &["list".into()]).unwrap();
        assert_eq!(saved["items"][0]["done"], true);
        assert_eq!(saved["items"][1]["title"], "Pay bill");
        run_at(&path, &["delete".into(), "1".into()]).unwrap();
        assert_eq!(
            run_at(&path, &["list".into()]).unwrap()["items"]
                .as_array()
                .unwrap()
                .len(),
            1
        );
        let _ = fs::remove_file(&path);
        let _ = fs::remove_file(path.with_extension("lock"));
    }
}
