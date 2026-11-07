use regex::Regex;
mod battery_control;
mod calendar_plans;
mod system_overview;
use serde_json::{json, Value};
use std::{
    collections::{BTreeMap, HashMap, HashSet},
    env, fs,
    io::{Read, Write},
    os::unix::fs::MetadataExt,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

const SCHEMA: i64 = 5;
const CONTRACT: &str = "1.1.0";
const REVISION: &str = "7.1-rust-operations";
fn now() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64()
}
fn home() -> PathBuf {
    env::var_os("HOME")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            eprintln!("ERROR: HOME must be set for Nyvorel Operations Center");
            std::process::exit(2);
        })
}
fn state_dir() -> PathBuf {
    env::var("OPERATIONS_CENTER_STATE_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| home().join(".local/state/nyvorel/operations-center"))
}
fn live_dir() -> PathBuf {
    env::var("OPERATIONS_CENTER_LIVE_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            PathBuf::from(
                env::var("XDG_RUNTIME_DIR")
                    .unwrap_or_else(|_| format!("/run/user/{}", unsafe { libc::getuid() })),
            )
            .join("nyvorel/operations-center")
        })
}
fn state_path() -> PathBuf {
    state_dir().join("state.json")
}
fn live_path() -> PathBuf {
    live_dir().join("live.json")
}
fn system_path() -> PathBuf {
    state_dir().join("system-cache.json")
}
fn read_json(p: &Path) -> Value {
    fs::read(p)
        .ok()
        .and_then(|b| serde_json::from_slice(&b).ok())
        .unwrap_or_else(|| json!({}))
}
fn write_json(p: &Path, v: &Value) -> Result<(), String> {
    fs::create_dir_all(p.parent().unwrap()).map_err(|e| e.to_string())?;
    let tmp = p.with_extension(format!("tmp-{}", std::process::id()));
    let bytes = serde_json::to_vec(v).map_err(|e| e.to_string())?;
    fs::write(&tmp, bytes).map_err(|e| e.to_string())?;
    fs::rename(&tmp, p).map_err(|e| e.to_string())
}
fn sval<'a>(v: &'a Value, k: &str) -> &'a str {
    v.get(k).and_then(Value::as_str).unwrap_or("")
}
fn ival(v: &Value, k: &str) -> i64 {
    v.get(k).and_then(Value::as_i64).unwrap_or(0)
}
fn fval(v: &Value, k: &str) -> f64 {
    v.get(k).and_then(Value::as_f64).unwrap_or(0.0)
}
fn arr(v: &Value, k: &str) -> Vec<Value> {
    v.get(k)
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
}
fn output(v: Value) {
    println!(
        "{}",
        serde_json::to_string(&v).unwrap_or_else(|_| "{}".into())
    );
}
fn command(parts: &[&str], timeout: Duration) -> Result<(i32, String, String), String> {
    if parts.is_empty() {
        return Err("empty command".into());
    }
    let mut child = Command::new(parts[0])
        .args(&parts[1..])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("{}: {e}", parts[0]))?;
    let mut stdout = child.stdout.take().ok_or("stdout unavailable")?;
    let mut stderr = child.stderr.take().ok_or("stderr unavailable")?;
    let stdout_reader = thread::spawn(move || {
        let mut bytes = Vec::new();
        let _ = stdout.read_to_end(&mut bytes);
        String::from_utf8_lossy(&bytes).into_owned()
    });
    let stderr_reader = thread::spawn(move || {
        let mut bytes = Vec::new();
        let _ = stderr.read_to_end(&mut bytes);
        String::from_utf8_lossy(&bytes).into_owned()
    });
    let start = Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                let out = stdout_reader.join().unwrap_or_default();
                let err = stderr_reader.join().unwrap_or_default();
                return Ok((status.code().unwrap_or(-1), out, err));
            }
            Ok(None) => {
                if start.elapsed() > timeout {
                    let _ = child.kill();
                    let _ = child.wait();
                    return Err(format!("{} timed out", parts[0]));
                }
                thread::sleep(Duration::from_millis(10));
            }
            Err(e) => return Err(e.to_string()),
        }
    }
}
fn human_bytes(kib: f64) -> String {
    if kib >= 1048576.0 {
        format!("{:.1} GB", kib / 1048576.0)
    } else if kib >= 1024.0 {
        format!("{:.1} MB", kib / 1024.0)
    } else {
        format!("{:.0} KB", kib)
    }
}
fn human_seconds(s: i64) -> String {
    if s >= 86400 {
        format!("{}d {}h", s / 86400, (s % 86400) / 3600)
    } else if s >= 3600 {
        format!("{}h {}m", s / 3600, (s % 3600) / 60)
    } else if s >= 60 {
        format!("{}m {}s", s / 60, s % 60)
    } else {
        format!("{}s", s)
    }
}
fn proc_uid(pid: i64) -> Option<u32> {
    fs::metadata(format!("/proc/{pid}")).ok().map(|m| m.uid())
}
fn start_ticks(pid: i64) -> i64 {
    let s = fs::read_to_string(format!("/proc/{pid}/stat")).unwrap_or_default();
    let f: Vec<&str> = s
        .rsplit_once(')')
        .map(|(_, r)| r.split_whitespace().collect())
        .unwrap_or_default();
    f.get(19).and_then(|x| x.parse().ok()).unwrap_or(0)
}
fn cwd(pid: i64) -> String {
    fs::read_link(format!("/proc/{pid}/cwd"))
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_default()
}
fn display_path(p: &str) -> String {
    let h = home().to_string_lossy().to_string();
    if p == h {
        "~".into()
    } else if p.starts_with(&(h.clone() + "/")) {
        format!("~{}", &p[h.len()..])
    } else {
        p.into()
    }
}
fn config_path() -> PathBuf {
    env::var("OPERATIONS_CENTER_CONFIG")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            PathBuf::from(
                env::var("XDG_CONFIG_HOME")
                    .unwrap_or_else(|_| home().join(".config").to_string_lossy().to_string()),
            )
            .join("nyvorel/operations-center.toml")
        })
}
fn config() -> toml::Value {
    fs::read_to_string(config_path())
        .ok()
        .and_then(|s| toml::from_str::<toml::Table>(&s).ok())
        .map(toml::Value::Table)
        .unwrap_or_else(|| toml::Value::Table(toml::map::Map::new()))
}
fn configured_action(key: &str) -> Result<Vec<String>, String> {
    let value = config()
        .get("actions")
        .and_then(|a| a.get(key))
        .and_then(toml::Value::as_str)
        .unwrap_or("")
        .trim()
        .to_string();
    if value.is_empty() {
        return Ok(vec![]);
    }
    let parts = shlex::split(&value).ok_or("invalid configured command")?;
    if parts.is_empty() {
        return Ok(vec![]);
    }
    command(&["which", &parts[0]], Duration::from_secs(1))
        .ok()
        .filter(|x| x.0 == 0)
        .ok_or_else(|| format!("configured {key} executable is unavailable: {}", parts[0]))?;
    Ok(parts)
}
fn runtime_ignored(cfg: &toml::Value, program: &str, args: &str, port: i64) -> bool {
    let runtime = cfg.get("runtime");
    if runtime
        .and_then(|r| r.get("ignore_ports"))
        .and_then(toml::Value::as_array)
        .is_some_and(|a| a.iter().any(|v| v.as_integer() == Some(port)))
    {
        return true;
    }
    let haystack = format!("{program} {args}").to_lowercase();
    runtime
        .and_then(|r| r.get("ignore_processes"))
        .and_then(toml::Value::as_array)
        .is_some_and(|a| {
            a.iter()
                .filter_map(toml::Value::as_str)
                .any(|v| !v.is_empty() && haystack.contains(&v.to_lowercase()))
        })
}
fn matching_detector(
    cfg: &toml::Value,
    program: &str,
    args: &str,
    cwd: &str,
    port: i64,
) -> Option<toml::Value> {
    cfg.get("detectors")
        .and_then(toml::Value::as_array)?
        .iter()
        .take(50)
        .find(|d| {
            let ports = d
                .get("ports")
                .and_then(toml::Value::as_array)
                .cloned()
                .unwrap_or_default();
            let process = d
                .get("process_contains")
                .and_then(toml::Value::as_str)
                .unwrap_or("")
                .to_lowercase();
            let path = d
                .get("cwd_contains")
                .and_then(toml::Value::as_str)
                .unwrap_or("")
                .to_lowercase();
            if !ports.is_empty() && !ports.iter().any(|v| v.as_integer() == Some(port)) {
                return false;
            }
            if !process.is_empty()
                && !format!("{program} {args}")
                    .to_lowercase()
                    .contains(&process)
            {
                return false;
            }
            if !path.is_empty() && !cwd.to_lowercase().contains(&path) {
                return false;
            }
            !ports.is_empty() || !process.is_empty() || !path.is_empty()
        })
        .cloned()
}
fn project_root(path: &str) -> String {
    if path.is_empty() {
        return String::new();
    }
    let mut p = PathBuf::from(path);
    let user_home = home();
    while p != user_home && p != Path::new("/") {
        if [
            "package.json",
            "pyproject.toml",
            "Cargo.toml",
            "go.mod",
            "composer.json",
            ".git",
        ]
        .iter()
        .any(|marker| p.join(marker).exists())
        {
            return p.to_string_lossy().to_string();
        }
        if !p.pop() {
            break;
        }
    }
    path.to_string()
}
fn project_name(path: &str) -> String {
    let p = project_root(path);
    if p.is_empty() || Path::new(&p) == home() {
        String::new()
    } else {
        Path::new(&p)
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string()
    }
}
fn sha_key(parts: &[&str]) -> String {
    let mut child = match Command::new("sha256sum")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
    {
        Ok(c) => c,
        Err(_) => return String::new(),
    };
    if let Some(mut input) = child.stdin.take() {
        let _ = input.write_all(parts.join("\0").as_bytes());
    }
    child
        .wait_with_output()
        .ok()
        .map(|o| {
            String::from_utf8_lossy(&o.stdout)
                .chars()
                .take(20)
                .collect()
        })
        .unwrap_or_default()
}

#[derive(Clone)]
struct Proc {
    pid: i64,
    ppid: i64,
    pgid: i64,
    sid: i64,
    elapsed: i64,
    cpu: f64,
    rss: i64,
    comm: String,
    args: String,
    start: i64,
}
fn processes() -> HashMap<i64, Proc> {
    let mut table = HashMap::new();
    let uid = unsafe { libc::getuid() };
    let uid_s = uid.to_string();
    let Ok((code, out, _)) = command(
        &[
            "ps",
            "-U",
            &uid_s,
            "-o",
            "pid=,ppid=,pgid=,sid=,etimes=,pcpu=,rss=,comm=,args=",
        ],
        Duration::from_secs(4),
    ) else {
        return table;
    };
    if code != 0 {
        return table;
    }
    let fields =
        Regex::new(r"^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+([\d.]+)\s+(\d+)\s+(\S+)\s+(.*)$")
            .unwrap();
    for line in out.lines() {
        let Some(f) = fields.captures(line) else {
            continue;
        };
        let Ok(pid) = f[1].parse::<i64>() else {
            continue;
        };
        if proc_uid(pid) != Some(uid) {
            continue;
        }
        table.insert(
            pid,
            Proc {
                pid,
                ppid: f[2].parse().unwrap_or(0),
                pgid: f[3].parse().unwrap_or(0),
                sid: f[4].parse().unwrap_or(0),
                elapsed: f[5].parse().unwrap_or(0),
                cpu: f[6].parse().unwrap_or(0.0),
                rss: f[7].parse().unwrap_or(0),
                comm: f[8].into(),
                args: f[9].into(),
                start: start_ticks(pid),
            },
        );
    }
    table
}
fn lineage(mut pid: i64, table: &HashMap<i64, Proc>) -> Vec<i64> {
    let mut result = Vec::new();
    let mut seen = HashSet::new();
    for _ in 0..64 {
        let Some(p) = table.get(&pid) else { break };
        if p.ppid <= 1 || !seen.insert(p.ppid) {
            break;
        }
        result.push(p.ppid);
        pid = p.ppid;
    }
    result
}
fn classify(args: &str, comm: &str) -> (String, Vec<String>, bool) {
    let l = args.to_lowercase();
    if l.contains("checkup-db-")
        || l.contains("checkupdates")
        || l.contains("pacman -qu")
        || l.contains("next/dist/compiled/jest-worker")
        || l.contains("jest-worker/processchild")
    {
        return (String::new(), vec![], false);
    }
    use std::sync::OnceLock;
    static TESTS: OnceLock<Vec<(&str, Regex)>> = OnceLock::new();
    let tests = TESTS.get_or_init(|| {
        [
            ("Build", r#"(?:^|[/\s'\"])(?:pnpm(?:\s+run)?\s+build(?:[:\w.-]*)?|npm\s+run\s+build(?:[:\w.-]*)?|(?:yarn|bun)(?:\s+run)?\s+build(?:[:\w.-]*)?|(?:next|vite|astro|nuxt)\s+build|cargo\s+build|cmake\s+--build|ninja|make)(?:\s|$)"#),
            ("Tests", r#"(?:^|[/\s'\"])(?:pnpm(?:\s+run)?\s+test(?:[:\w.-]*)?|npm(?:\s+run)?\s+test(?:[:\w.-]*)?|(?:yarn|bun)(?:\s+run)?\s+test(?:[:\w.-]*)?|vitest|jest|pytest|cargo\s+test)(?:\s|$)"#),
            ("Packages", r#"(?:^|[/\s'\"])(?:paru|yay|pacman)(?:\s|$)"#),
            ("Media", r#"(?:^|[/\s'\"])(?:ffmpeg|ffprobe)(?:\s|$)"#),
            ("Transfer", r#"(?:^|[/\s'\"])(?:rsync|wget|curl)(?:\s|$)"#),
            ("Agent", r#"(?:^|[/\s'\"])(?:codex|opencode)(?:\s|$)"#),
        ].into_iter().map(|(name, pattern)| (name, Regex::new(pattern).unwrap())).collect()
    });
    let mut kinds = Vec::new();
    for (kind, pattern) in tests {
        if pattern.is_match(&l) {
            kinds.push(kind.to_string());
        }
    }
    if kinds.is_empty() {
        return (String::new(), kinds, false);
    }
    let shell = ["sh", "bash", "dash", "zsh", "fish"].contains(&comm);
    let wrapper = shell
        && l.contains(" -c ")
        && (l.contains("&&") || l.contains("||") || l.contains(';') || kinds.len() > 1);
    let kind = if kinds.len() > 1 {
        "Workflow".to_string()
    } else {
        kinds[0].clone()
    };
    (kind, kinds, wrapper)
}
fn operations(table: &HashMap<i64, Proc>, runtime_pids: &HashSet<i64>) -> Vec<Value> {
    let mut candidates = HashMap::new();
    for (pid, p) in table {
        if !runtime_pids.contains(pid) {
            let c = classify(&p.args, &p.comm);
            if !c.0.is_empty() {
                candidates.insert(*pid, c);
            }
        }
    }
    let mut roots = HashMap::new();
    for (pid, c) in &candidates {
        let mut root = *pid;
        let p_project = project_root(&cwd(*pid));
        for a in lineage(*pid, table) {
            if let Some(ac) = candidates.get(&a) {
                let a_project = project_root(&cwd(a));
                if !p_project.is_empty() && !a_project.is_empty() && p_project != a_project {
                    continue;
                }
                if ac.2 || ac.0 == c.0 {
                    root = a;
                }
            }
        }
        roots.insert(*pid, root);
    }
    let mut members: HashMap<i64, Vec<i64>> = HashMap::new();
    for pid in table.keys() {
        let nearest = std::iter::once(*pid)
            .chain(lineage(*pid, table))
            .find(|p| roots.contains_key(p));
        if let Some(n) = nearest {
            members.entry(roots[&n]).or_default().push(*pid);
        }
    }
    let t = now();
    let mut rows = Vec::new();
    let unique: HashSet<i64> = roots.values().copied().collect();
    for pid in unique {
        let Some(p) = table.get(&pid) else { continue };
        let Some(c) = candidates.get(&pid) else {
            continue;
        };
        let list = members.get(&pid).cloned().unwrap_or_else(|| vec![pid]);
        let mem = list
            .iter()
            .filter_map(|id| table.get(id))
            .map(|x| x.rss)
            .sum::<i64>();
        let cpu = list
            .iter()
            .filter_map(|id| table.get(id))
            .map(|x| x.cpu)
            .sum::<f64>();
        let elapsed = list
            .iter()
            .filter_map(|id| table.get(id))
            .map(|x| x.elapsed)
            .max()
            .unwrap_or(p.elapsed);
        let path = cwd(pid);
        let key = format!("{pid}:{}", p.start);
        let pname = project_name(&path);
        let name = if c.0 == "Workflow" {
            c.1.join(" + ")
        } else {
            c.0.clone()
        };
        rows.push(json!({"key":key,"operation_id":key,"root_pid":pid,"root_start_ticks":p.start,"pid":pid,"pgid":p.pgid,"sid":p.sid,"name":name,"kind":c.0,"component_kinds":c.1,"workflow_wrapper":c.2,"project":pname,"project_key":sha_key(&[&project_root(&path)]),"elapsed":elapsed,"uptime":human_seconds(elapsed),"started_at":t-elapsed as f64,"cpu":(cpu*10.0).round()/10.0,"memory":human_bytes(mem as f64),"memory_kib":mem,"process_count":list.len(),"status":"Running","outcome":"running","last_seen_at":t}));
    }
    rows.sort_by_key(|row| std::cmp::Reverse(ival(row, "elapsed")));
    rows
}
fn runtime_kind(p: &Proc, path: &str, port: i64) -> String {
    let l = format!("{} {}", p.comm, p.args).to_lowercase();
    for (n, k) in [
        (5432, "PostgreSQL"),
        (6379, "Redis"),
        (3306, "MySQL"),
        (27017, "MongoDB"),
    ] {
        if port == n {
            return k.into();
        }
    }
    for (needle, k) in [
        ("wayvnc", "WayVNC"),
        ("tailscaled", "Tailscale"),
        ("next", "Next.js"),
        ("vite", "Vite"),
        ("astro", "Astro"),
        ("nuxt", "Nuxt"),
        ("uvicorn", "FastAPI"),
        ("fastapi", "FastAPI"),
        ("django", "Django"),
        ("flask", "Flask"),
        ("python", "Python"),
        ("node", "Node.js"),
    ] {
        if l.contains(needle) {
            return k.into();
        }
    }
    if Path::new(path).join("package.json").exists() {
        "Node.js".into()
    } else {
        p.comm.clone()
    }
}
fn protocol(kind: &str, args: &str, port: i64) -> String {
    let l = args.to_lowercase();
    if ["PostgreSQL", "Redis", "MySQL", "MongoDB"].contains(&kind) {
        "tcp".into()
    } else if kind == "WayVNC" {
        "vnc".into()
    } else if kind == "Tailscale" {
        "tailscale".into()
    } else if port == 22 {
        "ssh".into()
    } else if l.contains("https") {
        "https".into()
    } else if [
        "Next.js", "Vite", "Astro", "Nuxt", "FastAPI", "Django", "Flask",
    ]
    .contains(&kind)
        || l.contains("http.server")
        || l.contains("serve")
    {
        "http".into()
    } else {
        "tcp".into()
    }
}
fn proc_socket_addresses(table: &HashMap<i64, Proc>) -> Vec<(i64, String, i64)> {
    let uid = unsafe { libc::getuid() } as i64;
    let mut sockets = Vec::new();
    for (file, ipv6) in [("/proc/net/tcp", false), ("/proc/net/tcp6", true)] {
        let contents = fs::read_to_string(file).unwrap_or_default();
        for line in contents.lines().skip(1) {
            let f: Vec<_> = line.split_whitespace().collect();
            if f.len() < 10 || f[3] != "0A" || f[7].parse::<i64>().ok() != Some(uid) {
                continue;
            }
            let Some((address_hex, port_hex)) = f[1].rsplit_once(':') else {
                continue;
            };
            let (Ok(port), Ok(inode)) = (i64::from_str_radix(port_hex, 16), f[9].parse::<u64>())
            else {
                continue;
            };
            let address = if ipv6 {
                if address_hex.len() != 32 {
                    continue;
                }
                let mut bytes = [0u8; 16];
                let mut valid = true;
                for word in 0..4 {
                    for byte in 0..4 {
                        match u8::from_str_radix(
                            &address_hex[(word * 4 + 3 - byte) * 2..(word * 4 + 4 - byte) * 2],
                            16,
                        ) {
                            Ok(value) => bytes[word * 4 + byte] = value,
                            Err(_) => valid = false,
                        }
                    }
                }
                if !valid {
                    continue;
                }
                std::net::Ipv6Addr::from(bytes).to_string()
            } else {
                if address_hex.len() != 8 {
                    continue;
                }
                let bytes: Vec<_> = (0..4)
                    .filter_map(|i| u8::from_str_radix(&address_hex[i * 2..i * 2 + 2], 16).ok())
                    .collect();
                if bytes.len() != 4 {
                    continue;
                }
                format!("{}.{}.{}.{}", bytes[3], bytes[2], bytes[1], bytes[0])
            };
            if inode > 0 {
                sockets.push((inode, address, port));
            }
        }
    }
    let wanted: HashSet<u64> = sockets.iter().map(|s| s.0).collect();
    let mut owners: HashMap<u64, Vec<i64>> = HashMap::new();
    for pid in table.keys() {
        let Ok(dir) = fs::read_dir(format!("/proc/{pid}/fd")) else {
            continue;
        };
        for fd in dir.flatten() {
            let Ok(link) = fs::read_link(fd.path()) else {
                continue;
            };
            let target = link.to_string_lossy();
            let Some(text) = target
                .strip_prefix("socket:[")
                .and_then(|v| v.strip_suffix(']'))
            else {
                continue;
            };
            let Ok(inode) = text.parse::<u64>() else {
                continue;
            };
            if wanted.contains(&inode) {
                owners.entry(inode).or_default().push(*pid);
            }
        }
    }
    let mut result = Vec::new();
    for (inode, address, port) in sockets {
        for pid in owners.get(&inode).into_iter().flatten() {
            result.push((*pid, address.clone(), port));
        }
    }
    result
}
// A listening runtime is a process generation and port, not a bind-address row.
// In particular, ss uses * for some IPv6 sockets while /proc uses ::.
fn coalesce_runtimes(rows: Vec<Value>) -> Vec<Value> {
    let mut groups: BTreeMap<(i64, i64, i64), Vec<Value>> = BTreeMap::new();
    let mut unkeyed = Vec::new();
    for row in rows {
        let (pid, start, port) = (
            ival(&row, "pid"),
            ival(&row, "start_ticks"),
            ival(&row, "port"),
        );
        // Never merge incomplete process identities.
        if pid <= 0 || start <= 0 || port <= 0 {
            unkeyed.push(row);
        } else {
            groups.entry((pid, start, port)).or_default().push(row);
        }
    }
    for ((pid, start, port), group) in groups {
        // Prefer the ss wildcard spelling for display but keep ALL addresses.
        let preferred = group
            .iter()
            .find(|row| sval(row, "address") == "*")
            .or_else(|| group.iter().find(|row| sval(row, "address") == "0.0.0.0"))
            .or_else(|| group.iter().find(|row| sval(row, "address") == "::"))
            .unwrap_or(&group[0]);
        let mut result = preferred.clone();
        let mut addresses: Vec<String> = Vec::new();
        let mut aliases: Vec<String> = Vec::new();
        let mut managed = false;
        let mut all_interfaces = false;
        let mut exposed = false;
        for row in &group {
            let address = sval(row, "address");
            if !address.is_empty() && !addresses.iter().any(|x| x == address) {
                addresses.push(address.into());
            }
            let pin = sval(row, "pin_key");
            if !pin.is_empty() && !aliases.iter().any(|x| x == pin) {
                aliases.push(pin.into());
            }
            if let Some(items) = row.get("pin_aliases").and_then(Value::as_array) {
                for item in items.iter().filter_map(Value::as_str) {
                    if !aliases.iter().any(|x| x == item) {
                        aliases.push(item.into());
                    }
                }
            }
            managed |= row.get("managed_by_arch_remote").and_then(Value::as_bool) == Some(true);
            all_interfaces |=
                matches!(address, "*" | "::" | "0.0.0.0") || sval(row, "scope") == "All interfaces";
            exposed |= row.get("exposed").and_then(Value::as_bool) == Some(true)
                || !matches!(address, "127.0.0.1" | "::1" | "localhost");
        }
        addresses.sort();
        aliases.sort();
        // v2 pin identity is independent of PID, start time and listen address.
        // The old address-specific hashes are retained for existing saved pins.
        let stable_pin = sha_key(&[
            "runtime-pin-v2",
            sval(&result, "name"),
            sval(&result, "kind"),
            sval(&result, "cwd"),
            &port.to_string(),
        ]);
        if !stable_pin.is_empty() {
            result["pin_key"] = json!(stable_pin);
        }
        result["pin_aliases"] = json!(aliases);
        result["addresses"] = json!(addresses);
        result["key"] = json!(format!("{pid}:{start}:{port}"));
        result["exposed"] = json!(exposed);
        result["scope"] = json!(if all_interfaces {
            "All interfaces"
        } else if exposed {
            "Specific interface"
        } else {
            "Local"
        });
        result["managed_by_arch_remote"] = json!(managed);
        result["operations_stop_allowed"] = json!(!managed);
        unkeyed.push(result);
    }
    unkeyed
}

fn runtime_pins(row: &Value) -> Vec<String> {
    let mut keys = vec![sval(row, "pin_key").to_owned()];
    if let Some(aliases) = row.get("pin_aliases").and_then(Value::as_array) {
        keys.extend(aliases.iter().filter_map(Value::as_str).map(str::to_owned));
    }
    keys.retain(|key| !key.is_empty());
    keys.sort();
    keys.dedup();
    keys
}

fn listeners(table: &HashMap<i64, Proc>) -> Vec<Value> {
    let mut rows = Vec::new();
    let cfg = config();
    let re = Regex::new(r"pid=(\d+)").unwrap();
    let Ok((code, out, _)) = command(&["ss", "-H", "-ltnpe"], Duration::from_secs(4)) else {
        return rows;
    };
    if code != 0 {
        return rows;
    }
    let mut seen = HashSet::new();
    for line in out.lines() {
        let fields: Vec<_> = line.split_whitespace().collect();
        if fields.len() < 4 {
            continue;
        }
        let local = fields[3];
        let Some((address, port_s)) = local.rsplit_once(':') else {
            continue;
        };
        let Ok(port) = port_s.parse::<i64>() else {
            continue;
        };
        let address = address.trim_matches(['[', ']']);
        for cap in re.captures_iter(line) {
            let Ok(pid) = cap[1].parse::<i64>() else {
                continue;
            };
            let Some(p) = table.get(&pid) else { continue };
            if !seen.insert((pid, port, address.to_string())) {
                continue;
            }
            if runtime_ignored(&cfg, &p.comm, &p.args, port) {
                continue;
            }
            let path = cwd(pid);
            let detector = matching_detector(&cfg, &p.comm, &p.args, &path, port);
            let field = |key| {
                detector
                    .as_ref()
                    .and_then(|d| d.get(key))
                    .and_then(toml::Value::as_str)
                    .unwrap_or("")
                    .trim()
                    .to_string()
            };
            let kind = if field("kind").is_empty() {
                runtime_kind(p, &path, port)
            } else {
                field("kind")
            };
            let proto = if ["http", "https", "tcp"].contains(&field("protocol").as_str()) {
                field("protocol")
            } else {
                protocol(&kind, &p.args, port)
            };
            let low = format!("{} {}", p.comm, p.args).to_lowercase();
            let managed =
                (port == 5900 && low.contains("wayvnc") && low.contains("arch-remote.conf"))
                    || (port == 8000 && low.contains("lan-share/app.py"));
            let (name, area, managed_icon) = if managed && port == 5900 {
                (
                    "WayVNC Remote Desktop".into(),
                    "Remote Desktop",
                    "desktop_windows",
                )
            } else if managed {
                ("LAN Share".into(), "Private Share", "folder_shared")
            } else {
                (
                    if !field("name").is_empty() {
                        field("name")
                    } else if [
                        "Next.js", "Vite", "Astro", "Nuxt", "FastAPI", "Django", "Flask",
                        "Node.js", "Python",
                    ]
                    .contains(&kind.as_str())
                        && !project_name(&path).is_empty()
                    {
                        project_name(&path)
                    } else {
                        p.comm.clone()
                    },
                    "",
                    "",
                )
            };
            let exposed = !matches!(address, "127.0.0.1" | "::1" | "localhost");
            let scope = if !exposed {
                "Local"
            } else if matches!(address, "0.0.0.0" | "::" | "*") {
                "All interfaces"
            } else {
                "Specific interface"
            };
            let url = if proto == "http" || proto == "https" {
                format!("{proto}://localhost:{port}")
            } else {
                String::new()
            };
            let pin = sha_key(&[
                &p.comm,
                &project_root(&path),
                &kind,
                &port.to_string(),
                address,
            ]);
            let endpoint = if url.is_empty() {
                format!("{address}:{port}")
            } else {
                url.clone()
            };
            rows.push(json!({"key":format!("{pid}:{}:{port}:{address}",p.start),"pin_key":pin,"name":name,"kind":kind,"protocol":proto,"pid":pid,"start_ticks":p.start,"port":port,"address":address,"bind":format!("{address}:{port}"),"url":url,"endpoint":endpoint,"icon":if !field("icon").is_empty(){field("icon")}else if managed{managed_icon.into()}else if exposed{"public".into()}else{"dns".into()},"cwd":display_path(&path),"cpu":p.cpu,"memory":human_bytes(p.rss as f64),"memory_kib":p.rss,"uptime":human_seconds(p.elapsed),"elapsed":p.elapsed,"scope":scope,"exposed":exposed,"status":"Listening","managed_by_arch_remote":managed,"managed_area":area,"managed_icon":managed_icon,"operations_stop_allowed":!managed}));
        }
    }
    // Cross-check socket inodes with /proc to retain address provenance.
    // Different address representations are folded below, not shown as cards.
    for (pid, address, port) in proc_socket_addresses(table) {
        if !seen.insert((pid, port, address.clone())) {
            continue;
        }
        if let Some(mut row) = rows
            .iter()
            .find(|r| ival(r, "pid") == pid && ival(r, "port") == port)
            .cloned()
        {
            row["address"] = json!(address);
            row["bind"] = json!(format!("{address}:{port}"));
            if sval(&row, "url").is_empty() {
                row["endpoint"] = json!(format!("{address}:{port}"));
            }
            row["key"] = json!(format!(
                "{pid}:{}:{port}:{address}",
                ival(&row, "start_ticks")
            ));
            let p = table.get(&pid).unwrap();
            row["pin_key"] = json!(sha_key(&[
                &p.comm,
                &project_root(&cwd(pid)),
                sval(&row, "kind"),
                &port.to_string(),
                &address
            ]));
            rows.push(row);
        }
    }
    coalesce_runtimes(rows)
}
fn lock_state() -> Result<fs::File, String> {
    use std::os::fd::AsRawFd;
    fs::create_dir_all(state_dir()).map_err(|e| e.to_string())?;
    let file = fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(state_dir().join("state.lock"))
        .map_err(|e| e.to_string())?;
    if unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX) } != 0 {
        return Err("state lock failed".into());
    }
    Ok(file)
}
// Only one monitor scan may read/modify/write live.json at a time, even when
// a --fresh request overlaps the periodic systemd monitor.
fn lock_monitor() -> Result<fs::File, String> {
    use std::os::fd::AsRawFd;
    fs::create_dir_all(live_dir()).map_err(|e| e.to_string())?;
    let file = fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(live_dir().join("monitor.lock"))
        .map_err(|e| e.to_string())?;
    if unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX) } != 0 {
        return Err("monitor lock failed".into());
    }
    Ok(file)
}
fn normalize_state(mut st: Value) -> Value {
    if !st.is_object() {
        st = json!({})
    }
    if st
        .get("pinned_runtime_keys")
        .and_then(Value::as_array)
        .is_none()
    {
        st["pinned_runtime_keys"] = json!([])
    }
    if st
        .get("operation_history")
        .and_then(Value::as_array)
        .is_none()
    {
        st["operation_history"] = json!([])
    }
    st["schema_version"] = json!(SCHEMA);
    st
}
fn reconcile_jobs(mut current: Vec<Value>, previous: &[Value], t: f64) -> Vec<Value> {
    let mut unmatched: HashSet<String> = previous
        .iter()
        .map(|p| sval(p, "key").to_string())
        .collect();
    for row in &mut current {
        let direct = previous.iter().find(|p| sval(p, "key") == sval(row, "key"));
        let matched = if direct.is_some() {
            direct
        } else if ival(row, "sid") > 1 && ival(row, "pgid") > 1 {
            let matches: Vec<_> = previous
                .iter()
                .filter(|p| {
                    unmatched.contains(sval(p, "key"))
                        && ival(p, "sid") == ival(row, "sid")
                        && ival(p, "pgid") == ival(row, "pgid")
                        && sval(p, "project_key") == sval(row, "project_key")
                        && sval(p, "kind") == sval(row, "kind")
                        && (t - fval(p, "last_seen_at")).max(0.0) <= 15.0
                })
                .collect();
            if matches.len() == 1 {
                Some(matches[0])
            } else {
                None
            }
        } else {
            None
        };
        if let Some(old) = matched {
            unmatched.remove(sval(old, "key"));
            let stable = sval(old, "operation_id").to_string();
            row["key"] = json!(stable);
            row["operation_id"] = json!(stable);
            let started = fval(old, "started_at").min(fval(row, "started_at"));
            row["started_at"] = json!(started);
            if old.get("workflow_wrapper").and_then(Value::as_bool) == Some(true) {
                for key in ["kind", "name", "component_kinds", "workflow_wrapper"] {
                    row[key] = old[key].clone();
                }
            }
            let elapsed = (t - started).max(0.0) as i64;
            row["elapsed"] = json!(elapsed);
            row["uptime"] = json!(human_seconds(elapsed));
        }
    }
    current
}
fn monitor_once() -> Result<Value, String> {
    let _monitor_lock = lock_monitor()?;
    let table = processes();
    let runtimes = listeners(&table);
    let rp: HashSet<i64> = runtimes.iter().map(|r| ival(r, "pid")).collect();
    let discovered = operations(&table, &rp);
    let prev = read_json(&live_path());
    // Preserve running job identities during the v7.0 -> v7.1 handover.
    let same_backend = ival(&prev, "schema_version") == SCHEMA
        && [REVISION, "7.0-rust-operations"].contains(&sval(&prev, "backend_revision"));
    let prev_jobs = if same_backend {
        arr(&prev, "operations")
    } else {
        vec![]
    };
    let t = now();
    let jobs = reconcile_jobs(discovered, &prev_jobs, t);
    let curr: HashSet<String> = jobs
        .iter()
        .map(|j| sval(j, "operation_id").to_string())
        .collect();
    let prev_time = fval(&prev, "timestamp");
    let mut ended = Vec::new();
    if same_backend && prev_time > 0.0 {
        for old in prev_jobs {
            let key = sval(&old, "operation_id");
            if key.is_empty() || curr.contains(key) {
                continue;
            }
            let mut record = old.clone();
            if let Some(o) = record.as_object_mut() {
                for k in [
                    "root_pid",
                    "root_start_ticks",
                    "pid",
                    "pgid",
                    "sid",
                    "project_key",
                ] {
                    o.remove(k);
                }
                o.insert("ended_at".into(), json!(t));
                o.insert(
                    "end_observation_gap".into(),
                    json!((t - prev_time).max(0.0)),
                );
                o.insert(
                    "end_time_precision".into(),
                    json!(if t - prev_time <= 15.0 {
                        "observed"
                    } else {
                        "after-monitor-gap"
                    }),
                );
                o.insert("status".into(), json!("Ended"));
                o.insert("outcome".into(), json!("unknown"));
                o.insert("result_label".into(), json!("Result unknown"));
            }
            ended.push(record);
        }
    }
    if !ended.is_empty() {
        let _guard = lock_state()?;
        let mut st = normalize_state(read_json(&state_path()));
        let mut history = arr(&st, "operation_history");
        let mut existing: HashSet<String> = history
            .iter()
            .map(|j| sval(j, "operation_id").to_string())
            .collect();
        for e in ended.into_iter().rev() {
            if !existing.contains(sval(&e, "operation_id")) {
                existing.insert(sval(&e, "operation_id").to_string());
                history.insert(0, e);
            }
        }
        history.truncate(100);
        st["operation_history"] = json!(history);
        write_json(&state_path(), &st)?;
    }
    let payload = json!({"schema_version":SCHEMA,"ui_contract":CONTRACT,"backend_revision":REVISION,"timestamp":t,"runtimes":runtimes,"operations":jobs});
    write_json(&live_path(), &payload)?;
    Ok(payload)
}
fn recent_history() -> Vec<Value> {
    let st = normalize_state(read_json(&state_path()));
    let mut out = Vec::new();
    for mut item in arr(&st, "operation_history").into_iter().take(20) {
        let later = sval(&item, "end_time_precision") == "after-monitor-gap";
        let reference = if later {
            fval(&item, "last_seen_at")
        } else {
            fval(&item, "ended_at")
        };
        let age = (now() - reference).max(0.0) as i64;
        item["time_label"] = json!(format!(
            "{} {} ago",
            if later { "Last seen" } else { "Ended" },
            human_seconds(age)
        ));
        out.push(item)
    }
    out
}
fn failed_units() -> Vec<String> {
    let Ok((status, out, _)) = command(
        &["systemctl", "--user", "--failed", "--no-legend", "--plain"],
        Duration::from_secs(3),
    ) else {
        return vec![];
    };
    if status != 0 && status != 1 {
        return vec![];
    }
    out.lines()
        .filter_map(|l| l.split_whitespace().next().map(str::to_string))
        .take(8)
        .collect()
}
fn disk() -> Value {
    let path = b"/\0";
    let mut s = std::mem::MaybeUninit::<libc::statvfs>::uninit();
    if unsafe { libc::statvfs(path.as_ptr() as *const i8, s.as_mut_ptr()) } != 0 {
        return json!({"percent":0,"free":"—"});
    }
    let s = unsafe { s.assume_init() };
    let total = s.f_blocks as f64 * s.f_frsize as f64;
    let free = s.f_bfree as f64 * s.f_frsize as f64;
    let used = (total - free).max(0.0);
    json!({"percent":if total>0.0{((used/total*1000.0).round())/10.0}else{0.0},"free":human_bytes(free/1024.0),"used":human_bytes(used/1024.0),"total":human_bytes(total/1024.0)})
}
fn memory() -> Value {
    let s = fs::read_to_string("/proc/meminfo").unwrap_or_default();
    let mut vals = HashMap::new();
    for l in s.lines() {
        if let Some((k, v)) = l.split_once(':') {
            vals.insert(
                k,
                v.split_whitespace()
                    .next()
                    .unwrap_or("0")
                    .parse::<f64>()
                    .unwrap_or(0.0),
            );
        }
    }
    let total = *vals.get("MemTotal").unwrap_or(&0.0);
    let available = *vals.get("MemAvailable").unwrap_or(&0.0);
    let used = (total - available).max(0.0);
    json!({"percent":if total>0.0{(used/total*1000.0).round()/10.0}else{0.0},"used":human_bytes(used),"total":human_bytes(total)})
}
fn attention(runtimes: &[Value], monitor_fresh: bool) -> Vec<Value> {
    let mut items = Vec::new();
    if let Ok((_, out, _)) = command(&["hyprctl", "configerrors"], Duration::from_secs(3)) {
        if let Some(e) = out.lines().find(|l| !l.trim().is_empty()) {
            items.push(json!({"severity":"critical","icon":"error","title":"Hyprland config errors","detail":e.trim()}));
        }
    }
    let failed = failed_units();
    if !failed.is_empty() {
        items.push(json!({"severity":"critical","icon":"error","title":format!("{} failed user service(s)",failed.len()),"detail":failed.iter().take(3).cloned().collect::<Vec<_>>().join(", ")}));
    }
    let d = disk();
    let p = fval(&d, "percent");
    if p >= 80.0 {
        items.push(json!({"severity":if p>=90.0{"critical"}else{"warning"},"icon":"storage","title":if p>=90.0{"Disk space is critically low"}else{"Disk space is getting low"},"detail":format!("{}% used · {} free",p,sval(&d,"free"))}));
    }
    let exposed: Vec<_> = runtimes
        .iter()
        .filter(|r| {
            r.get("exposed").and_then(Value::as_bool) == Some(true)
                && r.get("managed_by_arch_remote").and_then(Value::as_bool) != Some(true)
        })
        .collect();
    if !exposed.is_empty() {
        items.push(json!({"severity":"info","icon":"public","title":"Services reachable beyond localhost","detail":exposed.iter().take(5).map(|r|format!("{} :{}",sval(r,"scope"),ival(r,"port"))).collect::<Vec<_>>().join(", ")}));
    }
    if !monitor_fresh {
        items.push(json!({"severity":"warning","icon":"history_toggle_off","title":"Operations monitor is not active","detail":"Rust monitor is not fresh; history may be incomplete."}));
    }
    items
}
fn snapshot(force_fresh: bool) -> Result<Value, String> {
    let mut live = read_json(&live_path());
    let cached_age = (now() - fval(&live, "timestamp")).max(0.0);
    let cache_valid = ival(&live, "schema_version") == SCHEMA
        && sval(&live, "backend_revision") == REVISION
        && cached_age <= 15.0;
    if force_fresh || !cache_valid {
        live = monitor_once()?;
    }
    // Normalize cached data too, for safe rollout while an old monitor exits.
    let mut runtimes = coalesce_runtimes(arr(&live, "runtimes"));
    let age = (now() - fval(&live, "timestamp")).max(0.0);
    let fresh = age <= 15.0;
    let jobs = arr(&live, "operations");
    let st = normalize_state(read_json(&state_path()));
    let pins: HashSet<String> = arr(&st, "pinned_runtime_keys")
        .iter()
        .filter_map(Value::as_str)
        .map(str::to_string)
        .collect();
    for r in &mut runtimes {
        r["pinned"] = json!(runtime_pins(r).iter().any(|key| pins.contains(key)));
    }
    runtimes.sort_by(|a, b| {
        let ap = a.get("pinned").and_then(Value::as_bool).unwrap_or(false);
        let bp = b.get("pinned").and_then(Value::as_bool).unwrap_or(false);
        bp.cmp(&ap).then(ival(a, "port").cmp(&ival(b, "port")))
    });
    let history = recent_history();
    let mut att = attention(&runtimes, fresh);
    let cached = read_json(&system_path());
    let updates = cached.get("updates").cloned().unwrap_or_else(|| json!({}));
    let update_count = updates.get("total").and_then(Value::as_i64).unwrap_or(-1);
    if update_count > 0 {
        att.push(json!({"severity":"maintenance","icon":"system_update","title":format!("{} package update(s) available",update_count),"detail":format!("{} official · {} AUR",ival(&updates,"official_count"),ival(&updates,"aur_count"))}));
    }
    let critical = att
        .iter()
        .filter(|x| matches!(sval(x, "severity"), "critical" | "warning"))
        .count();
    let maintenance = att
        .iter()
        .filter(|x| sval(x, "severity") == "maintenance")
        .count();
    let tracked: i64 = jobs.iter().map(|j| ival(j, "process_count")).sum();
    let local = runtimes
        .iter()
        .filter(|r| r.get("managed_by_arch_remote").and_then(Value::as_bool) != Some(true))
        .count();
    Ok(
        json!({"schema_version":SCHEMA,"ui_contract":CONTRACT,"backend_revision":REVISION,"timestamp":now(),"monitor":{"active":true,"age_seconds":age,"interval_seconds":5,"error":""},"runtimes":runtimes,"jobs":jobs,"job_groups":jobs,"job_history":history,"history_groups":history.iter().take(8).cloned().collect::<Vec<_>>(),"attention":att,"summary":{"runtime_count":runtimes.len(),"local_runtime_count":local,"remote_managed_count":runtimes.len()-local,"job_count":jobs.len(),"operation_count":jobs.len(),"tracked_process_count":tracked,"job_group_count":jobs.len(),"attention_count":critical,"maintenance_count":maintenance,"update_count":update_count}}),
    )
}
fn updates() -> Value {
    let mut official = Vec::new();
    let mut aur = Vec::new();
    let mut ok_off = false;
    let mut ok_aur = false;
    let mut off_src = "";
    let mut aur_src = "";
    if let Ok((code, out, _)) = command(&["checkupdates"], Duration::from_secs(10)) {
        if code == 0 || code == 2 {
            official = out
                .lines()
                .filter(|l| !l.trim().is_empty())
                .map(str::to_string)
                .collect();
            ok_off = true;
            off_src = "checkupdates";
        }
    }
    if !ok_off {
        if let Ok((code, out, _)) = command(&["pacman", "-Qu"], Duration::from_secs(6)) {
            if code == 0 || code == 1 {
                official = out
                    .lines()
                    .filter(|l| !l.trim().is_empty())
                    .map(str::to_string)
                    .collect();
                ok_off = true;
                off_src = "pacman -Qu";
            }
        }
    }
    if let Ok((code, out, _)) = command(&["paru", "-Qua"], Duration::from_secs(8)) {
        if code == 0 || code == 1 {
            aur = out
                .lines()
                .filter(|l| !l.trim().is_empty())
                .map(str::to_string)
                .collect();
            ok_aur = true;
            aur_src = "paru -Qua";
        }
    }
    json!({"official_count":if ok_off{official.len() as i64}else{-1},"aur_count":if ok_aur{aur.len() as i64}else{-1},"total":if ok_off&&ok_aur{(official.len()+aur.len()) as i64}else{-1},"official":official,"aur":aur,"official_known":ok_off,"aur_known":ok_aur,"official_source":off_src,"aur_source":aur_src,"source":format!("{} + {}",off_src,aur_src).trim_matches([' ','+']).trim()})
}
fn system(force: bool) -> Result<Value, String> {
    let old = read_json(&system_path());
    let t = now();
    let old_updates = old.get("updates").cloned().unwrap_or(Value::Null);
    let update_at = fval(&old, "updates_cached_at");
    let refresh = force || old_updates.is_null() || t - update_at >= 600.0;
    let up = if refresh { updates() } else { old_updates };
    let failed = failed_units();
    let load = fs::read_to_string("/proc/loadavg").unwrap_or_default();
    let f: Vec<_> = load.split_whitespace().take(3).collect();
    let hostname = fs::read_to_string("/etc/hostname")
        .unwrap_or_default()
        .trim()
        .to_string();
    let payload = json!({"schema_version":SCHEMA,"ui_contract":CONTRACT,"backend_revision":REVISION,"_cached_at":t,"updates_cached_at":if refresh{t}else{update_at},"updates":up,"failed_unit_count":failed.len(),"failed_units":failed,"disk":disk(),"memory":memory(),"load":if f.len()==3{f.join(" · ")}else{"—".into()},"hostname":hostname});
    write_json(&system_path(), &payload)?;
    Ok(payload)
}
fn safe_process(pid: i64, ticks: i64) -> Result<Proc, String> {
    if pid <= 1 {
        return Err("refusing unsafe PID".into());
    }
    if proc_uid(pid) != Some(unsafe { libc::getuid() }) {
        return Err("process missing or not owned by current user".into());
    }
    let p = processes().remove(&pid).ok_or("process no longer exists")?;
    if ticks > 0 && p.start != ticks {
        return Err("process identity changed; refusing stale PID action".into());
    }
    if p.args.contains("qs -c nyvorel") || p.args.contains("quickshell -c nyvorel") {
        return Err("refusing to stop the active Quickshell process".into());
    }
    Ok(p)
}
fn runtime_for_action(pid: i64, ticks: i64) -> Result<Value, String> {
    safe_process(pid, ticks)?;
    listeners(&processes())
        .into_iter()
        .find(|r| ival(r, "pid") == pid && (ticks == 0 || ival(r, "start_ticks") == ticks))
        .ok_or_else(|| "runtime is no longer listening".into())
}
fn spawn_detached(name: &str, args: &[&str], working: Option<&str>) -> Result<(), String> {
    let mut cmd = Command::new(name);
    cmd.args(args).stdout(Stdio::null()).stderr(Stdio::null());
    if let Some(dir) = working {
        cmd.current_dir(dir);
    }
    cmd.spawn()
        .map(|_| ())
        .map_err(|e| format!("cannot open {name}: {e}"))
}
fn spawn_configured(parts: &[String], extra: &[&str], working: Option<&str>) -> Result<(), String> {
    if parts.is_empty() {
        return Err("configured command is empty".into());
    }
    let mut cmd = Command::new(&parts[0]);
    cmd.args(&parts[1..])
        .args(extra)
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    if let Some(dir) = working {
        cmd.current_dir(dir);
    }
    cmd.spawn()
        .map(|_| ())
        .map_err(|e| format!("cannot open {}: {e}", parts[0]))
}
fn open_url(url: &str) -> Result<Value, String> {
    let re = Regex::new(r"^https?://(?:localhost|127\.0\.0\.1|\[::1\])(?::\d+)?(?:/.*)?$").unwrap();
    if !re.is_match(url) {
        return Err("only verified local HTTP(S) URLs can be opened".into());
    }
    spawn_detached("xdg-open", &[url], None)?;
    Ok(json!({"ok":true,"message":format!("Opened {url}")}))
}
fn terminal(pid: i64, ticks: i64) -> Result<Value, String> {
    safe_process(pid, ticks)?;
    let path = cwd(pid);
    if path.is_empty() {
        return Err("process working directory is unavailable".into());
    }
    let configured = configured_action("terminal")?;
    if !configured.is_empty() {
        spawn_configured(&configured, &[], Some(&path))?;
        return Ok(
            json!({"ok":true,"message":format!("Opened terminal in {}",display_path(&path))}),
        );
    }
    let mut chosen = "";
    for n in [
        "kitty",
        "foot",
        "alacritty",
        "wezterm",
        "konsole",
        "gnome-terminal",
    ] {
        if command(&["which", n], Duration::from_secs(1))
            .map(|x| x.0 == 0)
            .unwrap_or(false)
        {
            chosen = n;
            break;
        }
    }
    if chosen.is_empty() {
        return Err("no supported terminal found".into());
    }
    spawn_detached(chosen, &[], Some(&path))?;
    Ok(json!({"ok":true,"message":format!("Opened terminal in {}",display_path(&path))}))
}
fn folder_or_editor(pid: i64, ticks: i64, editor: bool) -> Result<Value, String> {
    safe_process(pid, ticks)?;
    let path = cwd(pid);
    if path.is_empty() {
        return Err("process working directory is unavailable".into());
    }
    if editor {
        let configured = configured_action("editor")?;
        if !configured.is_empty() {
            spawn_configured(&configured, &[&path], None)?;
            return Ok(json!({"ok":true,"message":format!("Opened {}",display_path(&path))}));
        }
        let mut chosen = "";
        for n in ["zed", "code", "codium", "kate", "subl"] {
            if command(&["which", n], Duration::from_secs(1))
                .map(|x| x.0 == 0)
                .unwrap_or(false)
            {
                chosen = n;
                break;
            }
        }
        if chosen.is_empty() {
            return Err("no supported editor found".into());
        }
        spawn_detached(chosen, &[&path], None)?;
    } else {
        let configured = configured_action("file_manager")?;
        if configured.is_empty() {
            spawn_detached("xdg-open", &[&path], None)?;
        } else {
            spawn_configured(&configured, &[&path], None)?;
        }
    }
    Ok(json!({"ok":true,"message":format!("Opened {}",display_path(&path))}))
}
fn copy_runtime(pid: i64, ticks: i64, mode: &str) -> Result<Value, String> {
    let r = runtime_for_action(pid, ticks)?;
    let value = match mode {
        "url" => sval(&r, "url").to_string(),
        "port" => ival(&r, "port").to_string(),
        "endpoint" => sval(&r, "endpoint").to_string(),
        _ => return Err("invalid copy mode".into()),
    };
    if value.is_empty() {
        return Err("runtime value is unavailable".into());
    }
    let mut child = Command::new("wl-copy")
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|_| "clipboard helper unavailable".to_string())?;
    if let Some(mut p) = child.stdin.take() {
        p.write_all(value.as_bytes()).map_err(|e| e.to_string())?;
    }
    if !child.wait().map_err(|e| e.to_string())?.success() {
        return Err("clipboard copy failed".into());
    }
    Ok(json!({"ok":true,"message":format!("Copied {mode}: {value}")}))
}
fn toggle_pin(key: &str) -> Result<Value, String> {
    if key.len() != 20 || !key.bytes().all(|x| x.is_ascii_hexdigit()) {
        return Err("invalid runtime pin key".into());
    }
    // Resolve old address-dependent keys before taking the state lock.
    let runtimes = coalesce_runtimes(arr(&read_json(&live_path()), "runtimes"));
    let selected = runtimes
        .iter()
        .find(|row| runtime_pins(row).iter().any(|k| k == key));
    let aliases = selected
        .map(runtime_pins)
        .unwrap_or_else(|| vec![key.into()]);
    let stable_key = selected
        .map(|r| sval(r, "pin_key"))
        .filter(|s| !s.is_empty())
        .unwrap_or(key);
    let _lock = lock_state()?;
    let mut st = normalize_state(read_json(&state_path()));
    let mut pins: Vec<String> = arr(&st, "pinned_runtime_keys")
        .iter()
        .filter_map(Value::as_str)
        .map(str::to_string)
        .collect();
    let was_pinned = pins.iter().any(|saved| aliases.iter().any(|a| a == saved));
    // Remove all legacy aliases when unpinning; otherwise they'd re-pin it.
    pins.retain(|saved| !aliases.iter().any(|a| a == saved));
    let pinned = if was_pinned {
        false
    } else {
        pins.push(stable_key.to_owned());
        true
    };
    if pins.len() > 30 {
        pins = pins[pins.len() - 30..].to_vec()
    }
    st["pinned_runtime_keys"] = json!(pins);
    write_json(&state_path(), &st)?;
    Ok(
        json!({"ok":true,"pinned":pinned,"message":if pinned{"Pinned runtime"}else{"Unpinned runtime"}}),
    )
}
fn same_process(pid: i64, ticks: i64) -> bool {
    proc_uid(pid) == Some(unsafe { libc::getuid() }) && start_ticks(pid) == ticks
}
fn wait_gone(pid: i64, ticks: i64, timeout: Duration) -> bool {
    let end = Instant::now() + timeout;
    while Instant::now() < end {
        if !same_process(pid, ticks) {
            return true;
        }
        thread::sleep(Duration::from_millis(50));
    }
    !same_process(pid, ticks)
}
fn signal(pid: i64, sig: i32) -> Result<(), String> {
    let r = unsafe { libc::kill(pid as i32, sig) };
    if r == 0 {
        Ok(())
    } else {
        Err(std::io::Error::last_os_error().to_string())
    }
}
fn owning_service(p: &Proc) -> Option<String> {
    let cgroup = fs::read_to_string(format!("/proc/{}/cgroup", p.pid)).ok()?;
    let path = cgroup.lines().find_map(|l| l.splitn(3, ':').nth(2))?;
    let unit = path
        .split('/')
        .rev()
        .find(|x| x.ends_with(".service") && !x.starts_with("user@"))?;
    if unit.contains("quickshell") || unit == "nyvorel-operations-monitor.service" {
        return None;
    }
    let (_, out, _) = command(
        &[
            "systemctl",
            "--user",
            "show",
            unit,
            "--property=MainPID",
            "--property=ControlGroup",
            "--property=ActiveState",
            "--no-pager",
        ],
        Duration::from_secs(3),
    )
    .ok()?;
    let props: HashMap<_, _> = out.lines().filter_map(|l| l.split_once('=')).collect();
    if props.get("MainPID").and_then(|x| x.parse::<i64>().ok()) != Some(p.pid) {
        return None;
    }
    if !["active", "activating", "reloading"].contains(&props.get("ActiveState")?) {
        return None;
    }
    let group = props.get("ControlGroup")?;
    if !path.starts_with(group) {
        return None;
    }
    Some(unit.into())
}
fn runtime_for_stop(rows: Vec<Value>, pid: i64, ticks: i64, key: &str) -> Option<Value> {
    rows.into_iter().find(|row| {
        ival(row, "pid") == pid
            && ival(row, "start_ticks") == ticks
            && (key.is_empty() || runtime_pins(row).iter().any(|alias| alias == key))
    })
}
fn stop_runtime(pid: i64, ticks: i64, key: &str) -> Result<Value, String> {
    // A single PID can own multiple listening ports. Match the clicked card's
    // pin identity, not whichever port happened to be enumerated first.
    safe_process(pid, ticks)?;
    let r = runtime_for_stop(listeners(&processes()), pid, ticks, key)
        .ok_or_else(|| "runtime is no longer listening or identity changed".to_string())?;
    if r.get("managed_by_arch_remote").and_then(Value::as_bool) == Some(true) {
        return Err("runtime is managed by Arch Remote".into());
    }
    let p = safe_process(pid, ival(&r, "start_ticks"))?;
    let unit = owning_service(&p);
    if let Some(ref u) = unit {
        let (code, _, err) = command(&["systemctl", "--user", "stop", u], Duration::from_secs(6))?;
        if code != 0 {
            return Err(format!("failed to stop owning service {u}: {}", err.trim()));
        }
    }
    if !wait_gone(pid, p.start, Duration::from_millis(500)) {
        safe_process(pid, p.start)?;
        signal(pid, libc::SIGTERM)?;
    }
    let forced = if !wait_gone(pid, p.start, Duration::from_millis(1500)) {
        safe_process(pid, p.start)?;
        signal(pid, libc::SIGKILL)?;
        true
    } else {
        false
    };
    if !wait_gone(pid, p.start, Duration::from_millis(500)) {
        return Err("runtime process survived stop".into());
    }
    Ok(
        json!({"ok":true,"message":if let Some(u)=unit{format!("Stopped runtime service {u}{}",if forced{" (forced teardown)"}else{""})}else{format!("Stopped runtime PID {pid}{}",if forced{" (SIGKILL escalation)"}else{""})}}),
    )
}
fn stop_operation(pid: i64, ticks: i64) -> Result<Value, String> {
    safe_process(pid, ticks)?;
    let table = processes();
    let mut descendants: Vec<i64> = table
        .keys()
        .filter(|p| **p != pid && lineage(**p, &table).contains(&pid))
        .copied()
        .collect();
    descendants.sort_by_key(|p| std::cmp::Reverse(lineage(*p, &table).len()));
    let mut count = 0;
    for child in descendants {
        if let Some(p) = table.get(&child) {
            if safe_process(child, p.start).is_ok() && signal(child, libc::SIGTERM).is_ok() {
                count += 1
            }
        }
    }
    safe_process(pid, ticks)?;
    signal(pid, libc::SIGTERM)?;
    count += 1;
    Ok(json!({"ok":true,"message":format!("Stopped operation ({count} processes)")}))
}
fn action(args: &[String]) -> Result<Value, String> {
    let arg = |i: usize| args.get(i).map(String::as_str).unwrap_or("");
    let num = |i: usize| arg(i).parse::<i64>().unwrap_or(0);
    match arg(0) {
        "open" => open_url(arg(1)),
        "terminal" => terminal(num(1), num(2)),
        "open-folder" => folder_or_editor(num(1), num(2), false),
        "open-editor" => folder_or_editor(num(1), num(2), true),
        "copy-runtime" => copy_runtime(num(1), num(2), arg(3)),
        "toggle-pin" => toggle_pin(arg(1)),
        "stop" => stop_runtime(num(1), num(2), arg(3)),
        "stop-operation" => stop_operation(num(1), num(2)),
        "open-remote" => {
            let config_name =
                env::var("OPERATIONS_CENTER_QS_CONFIG").unwrap_or_else(|_| "nyvorel".into());
            let (code, _, err) = command(
                &[
                    "qs",
                    "-c",
                    &config_name,
                    "ipc",
                    "call",
                    "archRemote",
                    "open",
                ],
                Duration::from_secs(3),
            )?;
            if code != 0 {
                Err(err)
            } else {
                Ok(json!({"ok":true,"message":"Opened Arch Remote"}))
            }
        }
        "migrate-state" => {
            let _lock = lock_state()?;
            let st = normalize_state(read_json(&state_path()));
            write_json(&state_path(), &st)?;
            Ok(
                json!({"ok":true,"schema_version":SCHEMA,"history_count":arr(&st,"operation_history").len(),"privacy_migrated":true}),
            )
        }
        "contract" => Ok(
            json!({"schema_version":SCHEMA,"ui_contract":CONTRACT,"backend_revision":REVISION,"monitor_interval_seconds":5,"monitor_fresh_seconds":15,"history_privacy":"minimal","process_scope":"current-user","runtime_command_exposed":false,"operation_command_exposed":false,"arch_remote_ownership":"positive-evidence","runtime_filters":true,"custom_detectors":true,"configurable_actions":true,"config_path":display_path(&config_path().to_string_lossy())}),
        ),
        "self-test" => {
            let checks = [
                (
                    "agent-detected",
                    classify("/usr/bin/codex", "codex").0 == "Agent",
                ),
                (
                    "incidental-name-ignored",
                    classify("/tmp/codex-notes/server", "server").0.is_empty(),
                ),
                (
                    "next-worker-ignored",
                    classify("next/dist/compiled/jest-worker/processChild.js", "node")
                        .0
                        .is_empty(),
                ),
                (
                    "process-identity",
                    start_ticks(std::process::id() as i64) > 0,
                ),
            ];
            Ok(
                json!({"ok":checks.iter().all(|x|x.1),"checks":checks.iter().map(|x|json!({"name":x.0,"pass":x.1})).collect::<Vec<_>>(),"scenario_count":checks.len()}),
            )
        }
        other => Err(format!("unknown command: {other}")),
    }
}
fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    if matches!(
        args.first().map(String::as_str),
        Some("battery-control" | "calendar")
    ) {
        let result = if args[0] == "battery-control" {
            battery_control::run(&args[1..])
        } else {
            calendar_plans::run(&args[1..])
        };
        match result {
            Ok(value) => output(value),
            Err(error) => {
                eprintln!("{error}");
                std::process::exit(1);
            }
        }
        return;
    }
    let result = match args.first().map(String::as_str).unwrap_or("") {
        "monitor" => loop {
            let start = Instant::now();
            if let Err(e) = monitor_once() {
                eprintln!("operations monitor: {e}")
            }
            let elapsed = start.elapsed();
            if elapsed < Duration::from_secs(5) {
                thread::sleep(Duration::from_secs(5) - elapsed)
            }
        },
        "monitor-once" => monitor_once(),
        "snapshot" => snapshot(args.iter().any(|arg| arg == "--fresh")),
        "system" => system(args.iter().any(|x| x == "--force")),
        "system-overview" => Ok(system_overview::snapshot()),
        _ => action(&args),
    };
    match result {
        Ok(v) => output(v),
        Err(e) => output(json!({"error":true,"message":e})),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn operation_classifier_avoids_incidental_names() {
        assert_eq!(classify("/usr/bin/codex", "codex").0, "Agent");
        assert_eq!(classify("/home/user/codex-notes/server", "server").0, "");
        assert_eq!(
            classify(
                "node /app/next/dist/compiled/jest-worker/processChild.js",
                "node"
            )
            .0,
            ""
        );
        assert_eq!(classify("pnpm run build", "pnpm").0, "Build");
    }

    #[test]
    fn process_handoff_keeps_operation_identity() {
        let old = json!({"key":"600:6000","operation_id":"600:6000","sid":50,"pgid":600,"project_key":"project","kind":"Build","started_at":1000.0,"last_seen_at":1010.0});
        let current = json!({"key":"601:6010","operation_id":"601:6010","sid":50,"pgid":600,"project_key":"project","kind":"Build","started_at":1008.0,"last_seen_at":1011.0});
        let rows = reconcile_jobs(vec![current], &[old], 1011.0);
        assert_eq!(sval(&rows[0], "operation_id"), "600:6000");
        assert_eq!(fval(&rows[0], "started_at"), 1000.0);
    }

    #[test]
    fn process_handoff_does_not_merge_other_projects() {
        let old = json!({"key":"600:6000","operation_id":"600:6000","sid":50,"pgid":600,"project_key":"alpha","kind":"Build","started_at":1000.0,"last_seen_at":1010.0});
        let current = json!({"key":"601:6010","operation_id":"601:6010","sid":50,"pgid":600,"project_key":"beta","kind":"Build","started_at":1008.0,"last_seen_at":1011.0});
        let rows = reconcile_jobs(vec![current], &[old], 1011.0);
        assert_eq!(sval(&rows[0], "operation_id"), "601:6010");
    }

    #[test]
    fn dual_stack_merges_without_losing_public_exposure_or_pins() {
        let a = json!({"pid":101,"start_ticks":55,"port":3017,"address":"*",
            "pin_key":"11111111111111111111","name":"mara","kind":"Next.js",
            "cwd":"~/mara","scope":"All interfaces","exposed":true,
            "managed_by_arch_remote":false});
        let b = json!({"pid":101,"start_ticks":55,"port":3017,"address":"::",
            "pin_key":"22222222222222222222","name":"mara","kind":"Next.js",
            "cwd":"~/mara","scope":"Specific interface","exposed":true});
        let rows = coalesce_runtimes(vec![a, b]);
        assert_eq!(rows.len(), 1);
        assert_eq!(sval(&rows[0], "scope"), "All interfaces");
        assert_eq!(sval(&rows[0], "address"), "*");
        assert_eq!(sval(&rows[0], "key"), "101:55:3017");
        assert_eq!(arr(&rows[0], "addresses").len(), 2);
        let keys = runtime_pins(&rows[0]);
        assert!(keys.iter().any(|k| k == "11111111111111111111"));
        assert!(keys.iter().any(|k| k == "22222222222222222222"));
        assert_eq!(sval(&rows[0], "pin_key").len(), 20);
    }

    #[test]
    fn independent_pid_generations_and_ports_never_merge() {
        let template = json!({"pid":101,"start_ticks":55,"port":3017,"address":"::",
           "pin_key":"11111111111111111111","name":"mara","kind":"Next.js","cwd":"~/mara"});
        let mut same_pid_new_generation = template.clone();
        same_pid_new_generation["start_ticks"] = json!(56);
        let mut other_port = template.clone();
        other_port["port"] = json!(3018);
        let mut other_pid = template.clone();
        other_pid["pid"] = json!(102);
        let rows = coalesce_runtimes(vec![
            template,
            same_pid_new_generation,
            other_port,
            other_pid,
        ]);
        assert_eq!(rows.len(), 4);
    }

    #[test]
    fn merged_managed_runtime_cannot_be_stopped() {
        let a = json!({"pid":101,"start_ticks":55,"port":5900,"address":"127.0.0.1",
          "managed_by_arch_remote":false,"name":"remote","kind":"tcp","cwd":"~"});
        let b = json!({"pid":101,"start_ticks":55,"port":5900,"address":"::",
          "managed_by_arch_remote":true,"name":"remote","kind":"tcp","cwd":"~"});
        let rows = coalesce_runtimes(vec![a, b]);
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0]["managed_by_arch_remote"], true);
        assert_eq!(rows[0]["operations_stop_allowed"], false);
    }

    #[test]
    fn stop_selects_clicked_port_not_first_runtime_of_same_process() {
        let a = json!({"pid":101,"start_ticks":55,"port":3017,"pin_key":"11111111111111111111"});
        let b = json!({"pid":101,"start_ticks":55,"port":3018,"pin_key":"22222222222222222222"});
        let selected =
            runtime_for_stop(vec![a.clone(), b.clone()], 101, 55, "22222222222222222222").unwrap();
        assert_eq!(ival(&selected, "port"), 3018);
        assert!(runtime_for_stop(vec![a, b], 101, 56, "22222222222222222222").is_none());
    }

    #[test]
    fn missing_start_tick_rows_are_not_merged() {
        let row = json!({"pid":101,"start_ticks":0,"port":3017});
        assert_eq!(coalesce_runtimes(vec![row.clone(), row]).len(), 2);
    }

    #[test]
    fn configured_runtime_port_is_filtered() {
        let cfg = toml::Value::Table(
            toml::from_str::<toml::Table>("[runtime]\nignore_ports = [1716]\n").unwrap(),
        );
        assert!(runtime_ignored(&cfg, "kdeconnectd", "kdeconnectd", 1716));
        assert!(!runtime_ignored(&cfg, "kdeconnectd", "kdeconnectd", 8080));
    }
}
