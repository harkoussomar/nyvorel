use serde_json::{Value, json};
use std::{
    collections::{BTreeMap, BTreeSet},
    env, fs,
    fs::{File, OpenOptions},
    io::Write,
    os::{fd::AsRawFd, unix::fs::PermissionsExt},
    path::{Path, PathBuf},
    process,
    time::{SystemTime, UNIX_EPOCH},
};

#[derive(Clone, Debug)]
pub struct Paths {
    pub config: PathBuf,
    pub state: PathBuf,
    pub backups: PathBuf,
    pub lock: PathBuf,
    pub xdg_config: PathBuf,
}

impl Paths {
    pub fn from_env() -> Self {
        let home = PathBuf::from(env::var_os("HOME").unwrap_or_else(|| "/".into()));
        let xdg_config = env::var_os("XDG_CONFIG_HOME")
            .filter(|value| !value.is_empty())
            .map(PathBuf::from)
            .unwrap_or_else(|| home.join(".config"));
        let state_dir = home.join(".local/state/nyvorel/settings-control");
        Self {
            config: xdg_config.join("nyvorel/config.json"),
            state: state_dir.join("state.json"),
            backups: state_dir.join("backups"),
            lock: state_dir.join("state.lock"),
            xdg_config,
        }
    }
}

pub struct Lock(File);

impl Lock {
    pub fn acquire(path: &Path) -> Result<Self, String> {
        fs::create_dir_all(path.parent().ok_or("lock has no parent")?)
            .map_err(|error| format!("{}: {error}", path.display()))?;
        let file = OpenOptions::new()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .open(path)
            .map_err(|error| format!("{}: {error}", path.display()))?;
        // flock is released automatically on exit, including abnormal exits.
        let result = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX) };
        if result != 0 {
            return Err(format!(
                "{}: {}",
                path.display(),
                std::io::Error::last_os_error()
            ));
        }
        Ok(Self(file))
    }
}

impl Drop for Lock {
    fn drop(&mut self) {
        unsafe { libc::flock(self.0.as_raw_fd(), libc::LOCK_UN) };
    }
}

pub fn default_state() -> Value {
    json!({"baseline": null, "history": [], "favorites": [], "last_backup": ""})
}

pub fn load_state(paths: &Paths) -> Result<Value, String> {
    fs::create_dir_all(paths.state.parent().ok_or("state has no parent")?)
        .map_err(|error| error.to_string())?;
    let mut value: Value = fs::read(&paths.state)
        .ok()
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or_else(default_state);
    if !value.is_object() {
        value = default_state();
    }
    let state = value.as_object_mut().expect("state is an object");
    for (key, default) in [
        ("baseline", Value::Null),
        ("history", json!([])),
        ("favorites", json!([])),
        ("last_backup", json!("")),
    ] {
        state.entry(key.to_string()).or_insert(default);
    }
    Ok(value)
}

fn save_state(paths: &Paths, value: &Value) -> Result<(), String> {
    atomic_write_json(&paths.state, value)
}

pub fn read_config(paths: &Paths) -> Result<Value, String> {
    let bytes =
        fs::read(&paths.config).map_err(|error| format!("{}: {error}", paths.config.display()))?;
    let value: Value = serde_json::from_slice(&bytes)
        .map_err(|error| format!("{}: {error}", paths.config.display()))?;
    if !value.is_object() {
        return Err(format!(
            "{}: root must be a JSON object",
            paths.config.display()
        ));
    }
    Ok(value)
}

fn atomic_write_json(path: &Path, value: &Value) -> Result<(), String> {
    let parent = path.parent().ok_or("output has no parent")?;
    fs::create_dir_all(parent).map_err(|error| format!("{}: {error}", parent.display()))?;
    let mut bytes = serde_json::to_vec_pretty(value).map_err(|error| error.to_string())?;
    bytes.push(b'\n');
    let mode = fs::metadata(path)
        .map(|metadata| metadata.permissions().mode() & 0o777)
        .unwrap_or(0o600);
    for attempt in 0..16 {
        let name = format!(
            ".{}.{}-{}-{attempt}.tmp",
            path.file_name().unwrap_or_default().to_string_lossy(),
            process::id(),
            now_nanos()
        );
        let temp = parent.join(name);
        let opened = OpenOptions::new().write(true).create_new(true).open(&temp);
        let mut file = match opened {
            Ok(file) => file,
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(format!("{}: {error}", temp.display())),
        };
        let write_result = (|| -> std::io::Result<()> {
            file.set_permissions(fs::Permissions::from_mode(mode))?;
            file.write_all(&bytes)?;
            file.sync_all()?;
            fs::rename(&temp, path)?;
            File::open(parent)?.sync_all()?;
            Ok(())
        })();
        if write_result.is_err() {
            let _ = fs::remove_file(&temp);
        }
        return write_result.map_err(|error| format!("{}: {error}", path.display()));
    }
    Err(format!(
        "{}: could not allocate temporary file",
        path.display()
    ))
}

fn now_nanos() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos()
}

fn now_secs() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64()
}

fn flatten(value: &Value, prefix: &str, output: &mut BTreeMap<String, Value>) {
    if let Some(object) = value.as_object() {
        for (key, child) in object {
            let path = if prefix.is_empty() {
                key.to_owned()
            } else {
                format!("{prefix}.{key}")
            };
            if child.is_object() {
                flatten(child, &path, output);
            } else {
                output.insert(path, child.clone());
            }
        }
    } else {
        output.insert(prefix.to_owned(), value.clone());
    }
}

fn diff_configs(old: &Value, new: &Value) -> Vec<Value> {
    let mut old_flat = BTreeMap::new();
    let mut new_flat = BTreeMap::new();
    flatten(old, "", &mut old_flat);
    flatten(new, "", &mut new_flat);
    let keys: BTreeSet<&String> = old_flat.keys().chain(new_flat.keys()).collect();
    let missing = json!({"__missing__": true});
    keys.into_iter()
        .filter_map(|key| {
            let before = old_flat.get(key).unwrap_or(&missing);
            let after = new_flat.get(key).unwrap_or(&missing);
            (before != after).then(|| json!({"path": key, "old": before, "new": after}))
        })
        .collect()
}

fn set_path(root: &mut Value, dotted: &str, value: &Value) {
    let mut parts = dotted.split('.').peekable();
    let mut node = root;
    while let Some(part) = parts.next() {
        if parts.peek().is_none() {
            if let Some(object) = node.as_object_mut() {
                if value.get("__missing__") == Some(&Value::Bool(true)) {
                    object.remove(part);
                } else {
                    object.insert(part.to_owned(), value.clone());
                }
            }
            return;
        }
        let object = node
            .as_object_mut()
            .expect("config path parent is an object");
        let child = object.entry(part.to_owned()).or_insert_with(|| json!({}));
        if !child.is_object() {
            *child = json!({});
        }
        node = child;
    }
}

pub fn snapshot(paths: &Paths, stored: &mut Value) -> Result<Value, String> {
    // A malformed/missing config still returns diagnostics; it never resets history.
    let current = match read_config(paths) {
        Ok(value) => value,
        Err(_) => return Ok(json!({})),
    };
    if !stored["baseline"].is_object() {
        stored["baseline"] = current;
        save_state(paths, stored)?;
        return Ok(json!({}));
    }
    let changes = diff_configs(&stored["baseline"], &current);
    if !changes.is_empty() {
        let event = json!({"timestamp": now_secs(), "changes": changes.into_iter().take(120).collect::<Vec<_>>()});
        let history = stored["history"]
            .as_array_mut()
            .ok_or("state history must be an array")?;
        history.push(event);
        if history.len() > 50 {
            history.drain(..history.len() - 50);
        }
        stored["baseline"] = current;
        save_state(paths, stored)?;
    }
    Ok(json!({}))
}

pub fn toggle_favorite(paths: &Paths, stored: &mut Value, id: &str) -> Result<Value, String> {
    let favorites = stored["favorites"]
        .as_array_mut()
        .ok_or("state favorites must be an array")?;
    let message = if let Some(index) = favorites
        .iter()
        .position(|value| value.as_str() == Some(id))
    {
        favorites.remove(index);
        "Removed from favorites"
    } else {
        favorites.push(json!(id));
        "Added to favorites"
    };
    if favorites.len() > 80 {
        favorites.drain(..favorites.len() - 80);
    }
    save_state(paths, stored)?;
    Ok(json!({"favorites": stored["favorites"], "message": message}))
}

fn make_backup(paths: &Paths, prefix: &str) -> Result<PathBuf, String> {
    fs::create_dir_all(&paths.backups).map_err(|error| error.to_string())?;
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let time = now as libc::time_t;
    let mut local = unsafe { std::mem::zeroed::<libc::tm>() };
    if unsafe { libc::localtime_r(&time, &mut local) }.is_null() {
        return Err("local time unavailable".into());
    }
    let stamp = format!(
        "{:04}{:02}{:02}-{:02}{:02}{:02}",
        local.tm_year + 1900,
        local.tm_mon + 1,
        local.tm_mday,
        local.tm_hour,
        local.tm_min,
        local.tm_sec
    );
    for suffix in 0..1000 {
        let name = if suffix == 0 {
            format!("{prefix}-{stamp}.json")
        } else {
            format!("{prefix}-{stamp}-{suffix}.json")
        };
        let target = paths.backups.join(name);
        if target.exists() {
            continue;
        }
        let temp = paths.backups.join(format!(
            ".{}.{}-{}.tmp",
            target.file_name().unwrap_or_default().to_string_lossy(),
            process::id(),
            now_nanos()
        ));
        let mut output = match OpenOptions::new().write(true).create_new(true).open(&temp) {
            Ok(file) => file,
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(format!("{}: {error}", temp.display())),
        };
        let result = (|| -> std::io::Result<()> {
            let mut source = File::open(&paths.config)?;
            output.set_permissions(source.metadata()?.permissions())?;
            std::io::copy(&mut source, &mut output)?;
            output.sync_all()?;
            fs::rename(&temp, &target)?;
            File::open(&paths.backups)?.sync_all()?;
            Ok(())
        })();
        if let Err(error) = result {
            let _ = fs::remove_file(&temp);
            return Err(format!("{}: {error}", target.display()));
        }
        return Ok(target);
    }
    Err("too many backups created this second".into())
}

pub fn backup(paths: &Paths, stored: &mut Value) -> Result<Value, String> {
    let target = make_backup(paths, "manual")?;
    stored["last_backup"] = json!(target.to_string_lossy());
    save_state(paths, stored)?;
    Ok(
        json!({"message": format!("Backup created: {}", target.file_name().unwrap_or_default().to_string_lossy())}),
    )
}

pub fn undo(paths: &Paths, stored: &mut Value) -> Result<Value, String> {
    let history = stored["history"]
        .as_array()
        .ok_or("state history must be an array")?;
    if history.is_empty() {
        return Ok(json!({"message": "Nothing to undo"}));
    }
    let mut current = read_config(paths)?;
    make_backup(paths, "before-undo")?;
    let event = stored["history"]
        .as_array_mut()
        .expect("history is an array")
        .pop()
        .expect("history is nonempty");
    let changes = event["changes"]
        .as_array()
        .ok_or("history changes must be an array")?;
    for change in changes {
        let path = change["path"]
            .as_str()
            .ok_or("history change path must be a string")?;
        set_path(&mut current, path, &change["old"]);
    }
    atomic_write_json(&paths.config, &current)?;
    stored["baseline"] = current;
    save_state(paths, stored)?;
    let count = changes.len();
    Ok(json!({"message": format!("Undid {count} change{}", if count == 1 { "" } else { "s" })}))
}

pub fn restore_latest(paths: &Paths, stored: &mut Value) -> Result<Value, String> {
    let mut candidates = Vec::new();
    if let Ok(entries) = fs::read_dir(&paths.backups) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path
                .extension()
                .is_some_and(|extension| extension == "json")
                && path.is_file()
            {
                let modified = entry
                    .metadata()
                    .ok()
                    .and_then(|metadata| metadata.modified().ok());
                candidates.push((modified, path));
            }
        }
    }
    candidates.sort_by(|a, b| b.0.cmp(&a.0).then_with(|| b.1.cmp(&a.1)));
    let Some((_, latest)) = candidates.into_iter().next() else {
        return Ok(json!({"message": "No configuration backup exists yet"}));
    };
    let name = latest.file_name().unwrap_or_default().to_string_lossy();
    let restored: Value = match fs::read(&latest)
        .ok()
        .and_then(|bytes| serde_json::from_slice::<Value>(&bytes).ok())
    {
        Some(value) if value.is_object() => value,
        _ => return Ok(json!({"message": format!("Backup is invalid: {name}")})),
    };
    make_backup(paths, "before-restore")?;
    atomic_write_json(&paths.config, &restored)?;
    stored["baseline"] = restored;
    stored["history"] = json!([]);
    save_state(paths, stored)?;
    Ok(json!({"message": format!("Restored {name}")}))
}

pub fn history_count(stored: &Value) -> usize {
    stored["history"].as_array().map_or(0, |events| {
        events
            .iter()
            .map(|event| event["changes"].as_array().map_or(0, Vec::len))
            .sum()
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn diff_and_undo_nested_paths() {
        let old = json!({"a": {"b": 1, "gone": true}, "arr": [1, 2]});
        let mut new = json!({"a": {"b": 2, "added": 3}, "arr": [3]});
        let diff = diff_configs(&old, &new);
        assert_eq!(diff.len(), 4);
        for change in &diff {
            set_path(&mut new, change["path"].as_str().unwrap(), &change["old"]);
        }
        assert_eq!(new, old);
    }

    #[test]
    fn empty_nested_objects_match_python_flattening() {
        assert!(diff_configs(&json!({"a": {}}), &json!({})).is_empty());
    }

    #[test]
    fn stale_temporary_file_does_not_replace_config() {
        let root = env::temp_dir().join(format!(
            "nyvorel-settings-test-{}-{}",
            process::id(),
            now_nanos()
        ));
        fs::create_dir_all(&root).unwrap();
        let config = root.join("config.json");
        atomic_write_json(&config, &json!({"value": 1})).unwrap();
        fs::write(root.join(".config.json.interrupted.tmp"), b"{broken").unwrap();
        let paths = Paths {
            config: config.clone(),
            state: root.join("state.json"),
            backups: root.join("backups"),
            lock: root.join("state.lock"),
            xdg_config: root.clone(),
        };
        assert_eq!(read_config(&paths).unwrap(), json!({"value": 1}));
        atomic_write_json(&config, &json!({"value": 2})).unwrap();
        assert_eq!(read_config(&paths).unwrap(), json!({"value": 2}));
        fs::remove_dir_all(root).unwrap();
    }
}
