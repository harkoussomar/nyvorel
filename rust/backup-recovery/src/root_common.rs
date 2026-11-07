use serde_json::{json, Value};
use std::ffi::CString;
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::os::fd::AsRawFd;
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

pub const BACKEND_REVISION: &str = "1.6.0-phase4-final";
pub const UI_CONTRACT: &str = "1.6.0";
pub const SCHEMA_VERSION: i64 = 2;

pub fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |duration| duration.as_secs() as i64)
}

#[derive(Clone)]
pub struct Paths {
    root: PathBuf,
}

impl Paths {
    pub fn new() -> Self {
        Self {
            root: std::env::var_os("NYVOREL_BACKUP_TEST_ROOT")
                .map(PathBuf::from)
                .unwrap_or_else(|| PathBuf::from("/")),
        }
    }

    pub fn at(&self, absolute: &str) -> PathBuf {
        self.root.join(absolute.trim_start_matches('/'))
    }

    pub fn state_dir(&self) -> PathBuf {
        self.at("/var/lib/backup-recovery")
    }

    pub fn state(&self, name: &str) -> PathBuf {
        self.state_dir().join(name)
    }

    pub fn config(&self) -> PathBuf {
        self.at("/etc/backup-recovery/config.json")
    }

    pub fn real_system(&self) -> bool {
        self.root == Path::new("/")
    }
}

impl Default for Paths {
    fn default() -> Self {
        Self::new()
    }
}

pub fn string(value: &Value) -> String {
    match value {
        Value::String(text) => text.clone(),
        Value::Null => String::new(),
        _ => value.to_string(),
    }
}

pub fn nonempty(value: &Value, default: &str) -> String {
    let text = string(value);
    if text.is_empty() {
        default.into()
    } else {
        text
    }
}

pub fn number(value: &Value) -> i64 {
    value
        .as_i64()
        .or_else(|| value.as_str().and_then(|text| text.parse().ok()))
        .unwrap_or(0)
}

pub fn boolish(value: &Value) -> bool {
    match value {
        Value::Null => false,
        Value::Bool(value) => *value,
        Value::Number(number) => number.as_f64().is_some_and(|number| number != 0.0),
        Value::String(text) => !text.is_empty(),
        Value::Array(items) => !items.is_empty(),
        Value::Object(items) => !items.is_empty(),
    }
}

pub fn read_json(path: &Path, default: Value) -> Value {
    fs::read(path)
        .ok()
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or(default)
}

pub fn merge(target: &mut Value, source: &Value) {
    if !target.is_object() {
        *target = json!({});
    }
    if let Some(fields) = source.as_object() {
        for (key, value) in fields {
            target[key] = value.clone();
        }
    }
}

pub struct Output {
    pub code: i32,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
}

impl Output {
    pub fn out(&self) -> String {
        String::from_utf8_lossy(&self.stdout).into_owned()
    }

    pub fn err(&self) -> String {
        String::from_utf8_lossy(&self.stderr).into_owned()
    }

    pub fn detail(&self) -> String {
        if self.stderr.is_empty() {
            self.out().trim().into()
        } else {
            self.err().trim().into()
        }
    }
}

// All external programs have a deadline and are reaped. Pipe-reader threads
// keep chatty tools from deadlocking while the parent waits.
pub fn run(program: &str, args: &[&str], timeout: u64) -> Output {
    run_env(program, args, timeout, &[])
}

pub fn run_env(program: &str, args: &[&str], timeout: u64, env: &[(String, String)]) -> Output {
    let mut command = Command::new(program);
    command
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    for (key, value) in env {
        command.env(key, value);
    }
    let child = command.spawn();
    let Ok(mut child) = child else {
        return Output {
            code: 124,
            stdout: Vec::new(),
            stderr: child
                .err()
                .map_or_else(Vec::new, |error| error.to_string().into_bytes()),
        };
    };
    let mut stdout = child.stdout.take().expect("piped stdout");
    let mut stderr = child.stderr.take().expect("piped stderr");
    let out_reader = thread::spawn(move || {
        let mut bytes = Vec::new();
        let _ = (&mut stdout).take(32 * 1024 * 1024).read_to_end(&mut bytes);
        bytes
    });
    let err_reader = thread::spawn(move || {
        let mut bytes = Vec::new();
        let _ = (&mut stderr).take(4 * 1024 * 1024).read_to_end(&mut bytes);
        bytes
    });
    let deadline = Instant::now() + Duration::from_secs(timeout);
    let code = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status.code().unwrap_or(1),
            Ok(None) if Instant::now() < deadline => thread::sleep(Duration::from_millis(20)),
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                break 124;
            }
        }
    };
    Output {
        code,
        stdout: out_reader.join().unwrap_or_default(),
        stderr: err_reader.join().unwrap_or_default(),
    }
}

pub fn atomic_json(path: &Path, value: &Value, mode: u32) -> Result<(), String> {
    let mut bytes = serde_json::to_vec_pretty(value).map_err(|error| error.to_string())?;
    bytes.push(b'\n');
    atomic_bytes(path, &bytes, mode)
}

pub fn atomic_bytes(path: &Path, bytes: &[u8], mode: u32) -> Result<(), String> {
    let parent = path.parent().ok_or("target has no parent")?;
    fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    let temp = parent.join(format!(
        ".{}.{}.{}.tmp",
        path.file_name().unwrap_or_default().to_string_lossy(),
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_or(0, |d| d.as_nanos())
    ));
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&temp)
        .map_err(|error| error.to_string())?;
    let result = (|| -> Result<(), String> {
        file.write_all(bytes).map_err(|error| error.to_string())?;
        file.sync_all().map_err(|error| error.to_string())?;
        fs::set_permissions(&temp, fs::Permissions::from_mode(mode))
            .map_err(|error| error.to_string())?;
        fs::rename(&temp, path).map_err(|error| error.to_string())?;
        if let Ok(directory) = File::open(parent) {
            let _ = directory.sync_all();
        }
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(temp);
    }
    result
}

pub struct Lock(File);

impl Lock {
    pub fn acquire(path: &Path, nonblocking: bool) -> Result<Self, String> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|error| error.to_string())?;
        }
        let file = OpenOptions::new()
            .read(true)
            .append(true)
            .create(true)
            .open(path)
            .map_err(|error| error.to_string())?;
        let flags = libc::LOCK_EX | if nonblocking { libc::LOCK_NB } else { 0 };
        if unsafe { libc::flock(file.as_raw_fd(), flags) } != 0 {
            return Err(std::io::Error::last_os_error().to_string());
        }
        Ok(Self(file))
    }
}

impl Drop for Lock {
    fn drop(&mut self) {
        unsafe {
            libc::flock(self.0.as_raw_fd(), libc::LOCK_UN);
        }
    }
}

pub fn user_ids(user: &str) -> Result<(u32, u32, String), String> {
    let name = CString::new(user).map_err(|_| "Invalid desktop user".to_string())?;
    let account = unsafe { libc::getpwnam(name.as_ptr()) };
    if account.is_null() {
        return Err(format!("Desktop user does not exist: {user}"));
    }
    let account = unsafe { &*account };
    let home = unsafe { std::ffi::CStr::from_ptr(account.pw_dir) }
        .to_string_lossy()
        .into_owned();
    Ok((account.pw_uid, account.pw_gid, home))
}

pub fn chown_root_group(path: &Path, group: u32, mode: u32) -> Result<(), String> {
    let cpath = CString::new(path.as_os_str().as_encoded_bytes())
        .map_err(|_| "Path contains NUL".to_string())?;
    if unsafe { libc::chown(cpath.as_ptr(), 0, group) } != 0 {
        return Err(std::io::Error::last_os_error().to_string());
    }
    fs::set_permissions(path, fs::Permissions::from_mode(mode)).map_err(|error| error.to_string())
}

pub fn file_mtime(path: &Path) -> i64 {
    fs::metadata(path)
        .ok()
        .and_then(|meta| meta.modified().ok())
        .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
        .map_or(0, |duration| duration.as_secs() as i64)
}

pub fn age_hours(timestamp: i64) -> Value {
    if timestamp == 0 {
        Value::Null
    } else {
        json!((((now() - timestamp).max(0) as f64 / 3600.0) * 10.0).round() / 10.0)
    }
}

pub fn freshness(age: &Value, overdue: i64) -> &'static str {
    match age.as_f64() {
        None => "unknown",
        Some(age) if age > overdue as f64 => "stale",
        Some(_) => "fresh",
    }
}

pub fn hostname() -> String {
    let mut buffer = [0u8; 256];
    if unsafe { libc::gethostname(buffer.as_mut_ptr().cast(), buffer.len()) } != 0 {
        return String::new();
    }
    let length = buffer
        .iter()
        .position(|byte| *byte == 0)
        .unwrap_or(buffer.len());
    String::from_utf8_lossy(&buffer[..length]).into_owned()
}
