use serde_json::{json, Value};
use std::{fs, path::Path};

fn number_after_colon(text: &str, name: &str) -> Option<f64> {
    text.lines().find_map(|line| {
        let (key, value) = line.split_once(':')?;
        (key == name)
            .then(|| value.split_whitespace().next()?.parse().ok())
            .flatten()
    })
}

fn pressure(path: &str) -> Option<f64> {
    let content = fs::read_to_string(path).ok()?;
    content
        .lines()
        .find(|line| line.starts_with("some "))?
        .split_whitespace()
        .find_map(|part| part.strip_prefix("avg10="))?
        .parse()
        .ok()
}

fn cpu_clock() -> Option<f64> {
    let content = fs::read_to_string("/proc/cpuinfo").ok()?;
    let clocks: Vec<f64> = content
        .lines()
        .filter_map(|line| {
            let (key, value) = line.split_once(':')?;
            (key.trim() == "cpu MHz")
                .then(|| value.trim().parse::<f64>().ok())
                .flatten()
        })
        .collect();
    if clocks.is_empty() {
        None
    } else {
        Some(clocks.iter().sum::<f64>() / clocks.len() as f64 / 1000.0)
    }
}

fn cpu_temperature() -> Option<f64> {
    for entry in fs::read_dir("/sys/class/hwmon").ok()?.flatten() {
        let path = entry.path();
        let Ok(name) = fs::read_to_string(path.join("name")) else {
            continue;
        };
        if !matches!(name.trim(), "coretemp" | "k10temp" | "zenpower") {
            continue;
        }
        let Ok(value) = fs::read_to_string(path.join("temp1_input")) else {
            continue;
        };
        if let Ok(millidegrees) = value.trim().parse::<f64>() {
            return Some(millidegrees / 1000.0);
        }
    }
    None
}

fn root_inode_percent() -> Option<f64> {
    let mut result = std::mem::MaybeUninit::<libc::statvfs>::uninit();
    if unsafe { libc::statvfs(c"/".as_ptr(), result.as_mut_ptr()) } != 0 {
        return None;
    }
    let stat = unsafe { result.assume_init() };
    if stat.f_files == 0 {
        return None;
    }
    Some((stat.f_files.saturating_sub(stat.f_ffree)) as f64 / stat.f_files as f64 * 100.0)
}

fn parse_process_stat(text: &str) -> Option<(String, u64, u64, i64)> {
    let (_, after_open) = text.split_once('(')?;
    let (name, after_close) = after_open.rsplit_once(')')?;
    let fields: Vec<&str> = after_close.split_whitespace().collect();
    // Field 3 (state) is fields[0]; utime=14, stime=15, starttime=22, rss=24.
    if fields.len() <= 21 {
        return None;
    }
    let total_ticks = fields[11].parse::<u64>().ok()? + fields[12].parse::<u64>().ok()?;
    let start_ticks = fields[19].parse::<u64>().ok()?;
    let rss_pages = fields[21].parse::<i64>().ok()?;
    Some((name.to_string(), total_ticks, start_ticks, rss_pages))
}

fn processes(uptime: f64, memory_total_kib: f64) -> (usize, String, f64, f64) {
    let ticks = unsafe { libc::sysconf(libc::_SC_CLK_TCK) }.max(1) as f64;
    let page_kib = unsafe { libc::sysconf(libc::_SC_PAGESIZE) }.max(1) as f64 / 1024.0;
    let mut count = 0;
    let mut top = (String::new(), 0.0, 0.0);
    let Ok(entries) = fs::read_dir(Path::new("/proc")) else {
        return (0, "—".into(), 0.0, 0.0);
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if !entry
            .file_name()
            .to_string_lossy()
            .bytes()
            .all(|byte| byte.is_ascii_digit())
        {
            continue;
        }
        count += 1;
        let Ok(stat) = fs::read_to_string(path.join("stat")) else {
            continue;
        };
        let Some((name, total_ticks, start_ticks, rss_pages)) = parse_process_stat(&stat) else {
            continue;
        };
        let elapsed = uptime - start_ticks as f64 / ticks;
        if elapsed <= 0.0 {
            continue;
        }
        let cpu = total_ticks as f64 / ticks / elapsed * 100.0;
        if cpu > top.1 {
            let memory = if memory_total_kib > 0.0 {
                rss_pages.max(0) as f64 * page_kib / memory_total_kib * 100.0
            } else {
                0.0
            };
            top = (name, cpu, memory);
        }
    }
    (
        count,
        if top.0.is_empty() {
            "—".into()
        } else {
            top.0
        },
        top.1,
        top.2,
    )
}

fn text_or_dash(value: Option<f64>, unit: &str, decimals: usize) -> String {
    value
        .map(|v| format!("{v:.decimals$}{unit}"))
        .unwrap_or_else(|| "—".into())
}

pub fn snapshot() -> Value {
    let memory = fs::read_to_string("/proc/meminfo").unwrap_or_default();
    let load = fs::read_to_string("/proc/loadavg").unwrap_or_default();
    let loads: Vec<f64> = load
        .split_whitespace()
        .take(3)
        .filter_map(|s| s.parse().ok())
        .collect();
    let uptime = fs::read_to_string("/proc/uptime")
        .ok()
        .and_then(|s| s.split_whitespace().next()?.parse().ok())
        .unwrap_or(0.0);
    let total_memory = number_after_colon(&memory, "MemTotal").unwrap_or(0.0);
    let (process_count, top_name, top_cpu, top_memory) = processes(uptime, total_memory);
    json!({
        "disk": super::disk(),
        "load": loads,
        "logicalCpuCount": std::thread::available_parallelism().map(|n| n.get()).unwrap_or(1),
        "cpuClock": text_or_dash(cpu_clock(), " GHz", 2),
        "cpuTemperature": text_or_dash(cpu_temperature(), " °C", 1),
        "cachedMemory": text_or_dash(number_after_colon(&memory, "Cached").map(|v| v / 1048576.0), " GB", 1),
        "cpuPressure": text_or_dash(pressure("/proc/pressure/cpu"), "%", 2),
        "memoryPressure": text_or_dash(pressure("/proc/pressure/memory"), "%", 2),
        "ioPressure": text_or_dash(pressure("/proc/pressure/io"), "%", 2),
        "rootInodes": text_or_dash(root_inode_percent(), "%", 0),
        "processCount": process_count,
        "topProcessName": top_name,
        "topProcessCpu": format!("{top_cpu:.1}"),
        "topProcessMemory": format!("{top_memory:.1}"),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stat_parser_handles_spaces_and_parentheses_in_process_name() {
        let mut fields = vec!["0"; 22];
        fields[0] = "S";
        fields[11] = "120";
        fields[12] = "30";
        fields[19] = "500";
        fields[21] = "4";
        let stat = format!("123 (editor (work)) {}", fields.join(" "));
        let parsed = parse_process_stat(&stat).unwrap();
        assert_eq!(parsed.0, "editor (work)");
        assert_eq!(parsed.1, 150);
        assert_eq!(parsed.2, 500);
        assert_eq!(parsed.3, 4);
    }
}
