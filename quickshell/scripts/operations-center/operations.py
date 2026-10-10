#!/usr/bin/env python3
from __future__ import annotations

import fcntl
import hashlib
import ipaddress
import json
import os
import re
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import tomllib
from contextlib import contextmanager
from pathlib import Path

HOME = Path.home()
DEFAULT_STATE_DIR = HOME / ".local/state/nyvorel/operations-center"
STATE_DIR = Path(
    os.environ.get("OPERATIONS_CENTER_STATE_DIR", str(DEFAULT_STATE_DIR))
).expanduser()
STATE_PATH = STATE_DIR / "state.json"
STATE_LOCK_PATH = STATE_DIR / "state.lock"
SYSTEM_CACHE_PATH = STATE_DIR / "system-cache.json"
ATTENTION_CACHE_PATH = STATE_DIR / "attention-cache.json"
RUNTIME_BASE = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
DEFAULT_LIVE_DIR = RUNTIME_BASE / "nyvorel/operations-center"
LIVE_DIR = Path(
    os.environ.get("OPERATIONS_CENTER_LIVE_DIR", str(DEFAULT_LIVE_DIR))
).expanduser()
LIVE_PATH = LIVE_DIR / "live.json"
SCHEMA_VERSION = 5
UI_CONTRACT = "1.1.0"
BACKEND_REVISION = "6.1-runtime-control"
HISTORY_LIMIT = 100
MONITOR_INTERVAL = 5.0
MONITOR_FRESH_SECONDS = 15.0
ATTENTION_CACHE_SECONDS = 15.0
QS_CONFIG = os.environ.get("OPERATIONS_CENTER_QS_CONFIG", "nyvorel").strip() or "nyvorel"
XDG_CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", str(HOME / ".config"))).expanduser()
CONFIG_PATH = Path(
    os.environ.get(
        "OPERATIONS_CENTER_CONFIG",
        str(XDG_CONFIG_HOME / "nyvorel/operations-center.toml"),
    )
).expanduser()

DB_PORTS = {
    3306: "MySQL",
    5432: "PostgreSQL",
    6379: "Redis",
    27017: "MongoDB",
}

PROJECT_MARKERS = (
    "package.json",
    "pyproject.toml",
    "Cargo.toml",
    "go.mod",
    "composer.json",
    ".git",
)


def atomic_json(path: Path, payload) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(
        prefix=path.name + ".",
        suffix=".tmp",
        dir=path.parent,
    )
    temp_path = Path(temp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_path, path)
    finally:
        temp_path.unlink(missing_ok=True)


def load_json(path: Path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default



def default_config() -> dict:
    return {
        "actions": {
            "terminal": "",
            "editor": "",
            "file_manager": "",
        },
        "runtime": {
            "ignore_ports": [],
            "ignore_processes": [],
        },
        "detectors": [],
    }


def _string_list(value) -> list[str]:
    if not isinstance(value, list):
        return []
    return [str(item).strip() for item in value if str(item).strip()]


def load_config() -> dict:
    payload = default_config()
    try:
        raw = tomllib.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return payload
    except Exception:
        return payload
    if not isinstance(raw, dict):
        return payload

    actions = raw.get("actions", {})
    if isinstance(actions, dict):
        for key in ("terminal", "editor", "file_manager"):
            value = actions.get(key, "")
            payload["actions"][key] = str(value).strip() if value is not None else ""

    runtime = raw.get("runtime", {})
    if isinstance(runtime, dict):
        ports = []
        for item in runtime.get("ignore_ports", []):
            try:
                port = int(item)
            except (TypeError, ValueError):
                continue
            if 1 <= port <= 65535:
                ports.append(port)
        payload["runtime"]["ignore_ports"] = sorted(set(ports))
        payload["runtime"]["ignore_processes"] = _string_list(
            runtime.get("ignore_processes", [])
        )

    detectors = raw.get("detectors", [])
    if isinstance(detectors, list):
        clean = []
        for item in detectors[:50]:
            if not isinstance(item, dict):
                continue
            row = {
                "name": str(item.get("name", "")).strip(),
                "kind": str(item.get("kind", "")).strip(),
                "icon": str(item.get("icon", "")).strip(),
                "protocol": str(item.get("protocol", "")).strip().lower(),
                "process_contains": str(item.get("process_contains", "")).strip().lower(),
                "cwd_contains": str(item.get("cwd_contains", "")).strip().lower(),
                "ports": [],
            }
            for port_value in item.get("ports", []):
                try:
                    port = int(port_value)
                except (TypeError, ValueError):
                    continue
                if 1 <= port <= 65535:
                    row["ports"].append(port)
            row["ports"] = sorted(set(row["ports"]))
            if row["protocol"] not in ("", "http", "https", "tcp"):
                row["protocol"] = ""
            if row["name"] or row["kind"] or row["process_contains"] or row["cwd_contains"] or row["ports"]:
                clean.append(row)
        payload["detectors"] = clean
    return payload


def runtime_ignored(config: dict, program: str, args: str, port: int) -> bool:
    runtime = config.get("runtime", {})
    if port in set(runtime.get("ignore_ports", [])):
        return True
    haystack = f"{program} {args}".lower()
    return any(token.lower() in haystack for token in runtime.get("ignore_processes", []))


def detector_matches(detector: dict, program: str, args: str, cwd: str, port: int) -> bool:
    ports = detector.get("ports", [])
    if ports and port not in ports:
        return False
    process_contains = str(detector.get("process_contains", "")).lower()
    if process_contains and process_contains not in f"{program} {args}".lower():
        return False
    cwd_contains = str(detector.get("cwd_contains", "")).lower()
    if cwd_contains and cwd_contains not in cwd.lower():
        return False
    return bool(ports or process_contains or cwd_contains)


def matching_detector(config: dict, program: str, args: str, cwd: str, port: int) -> dict:
    for detector in config.get("detectors", []):
        if detector_matches(detector, program, args, cwd, port):
            return detector
    return {}


def configured_command(key: str) -> list[str]:
    config = load_config()
    configured = str(config.get("actions", {}).get(key, "")).strip()
    if not configured:
        return []
    parts = shlex.split(configured)
    if not parts:
        return []
    found = executable(parts[0])
    if not found:
        raise ValueError(f"configured {key} executable is unavailable: {parts[0]}")
    parts[0] = found
    return parts


def default_state() -> dict:
    return {
        "schema_version": SCHEMA_VERSION,
        "pinned_runtime_keys": [],
        "operation_history": [],
    }


SAFE_HISTORY_KEYS = {
    "key",
    "operation_id",
    "name",
    "kind",
    "component_kinds",
    "workflow_wrapper",
    "project",
    "elapsed",
    "uptime",
    "started_at",
    "cpu",
    "memory",
    "memory_kib",
    "process_count",
    "status",
    "outcome",
    "last_seen_at",
    "ended_at",
    "end_observation_gap",
    "end_time_precision",
    "result_label",
}


def sanitize_history_record(item) -> dict:
    if not isinstance(item, dict):
        return {}
    row = {key: item[key] for key in SAFE_HISTORY_KEYS if key in item}
    # Historical rows must never carry process-control identity. A finished
    # operation cannot be acted on, and retaining PID/command/cwd data only
    # increases privacy risk.
    row.pop("root_pid", None)
    row.pop("root_start_ticks", None)
    return row


def normalize_state(payload) -> dict:
    if not isinstance(payload, dict):
        payload = {}

    pins = [
        str(item) for item in payload.get("pinned_runtime_keys", [])
        if re.fullmatch(r"[0-9a-f]{20}", str(item))
    ][-30:]

    # Schema 5 intentionally drops legacy raw process histories. Older
    # generations could persist full command lines, cwd/project paths, and
    # member PIDs. The install backup remains the rollback/audit source; the
    # live state is migrated to the minimum data the UI actually needs.
    history = []
    for item in list(payload.get("operation_history", []))[:HISTORY_LIMIT]:
        clean = sanitize_history_record(item)
        if clean:
            history.append(clean)

    return {
        "schema_version": SCHEMA_VERSION,
        "pinned_runtime_keys": pins,
        "operation_history": history[:HISTORY_LIMIT],
    }


@contextmanager
def locked_state():
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    with STATE_LOCK_PATH.open("a+", encoding="utf-8") as lock_handle:
        fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)
        payload = normalize_state(load_json(STATE_PATH, default_state()))
        try:
            yield payload
        finally:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)


def state() -> dict:
    # Shared locks are avoided because STATE_PATH is atomically replaced. Reading
    # an old or new complete JSON document is safe; writers use locked_state().
    return normalize_state(load_json(STATE_PATH, default_state()))


def save_state(payload: dict) -> None:
    payload = normalize_state(payload)
    atomic_json(STATE_PATH, payload)


def executable(name: str) -> str | None:
    found = shutil.which(name)
    if found:
        return found
    candidate = Path("/usr/bin") / name
    if candidate.exists():
        return str(candidate)
    return None


def run(command, timeout=4.0):
    try:
        return subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            check=False,
        )
    except Exception as error:
        return subprocess.CompletedProcess(command, 127, "", str(error))


def human_bytes(kib: int | float) -> str:
    value = float(kib) * 1024.0
    for suffix in ("B", "KB", "MB", "GB", "TB"):
        if value < 1024.0 or suffix == "TB":
            if suffix in ("B", "KB"):
                return f"{value:.0f} {suffix}"
            return f"{value:.1f} {suffix}"
        value /= 1024.0
    return "0 B"


def human_seconds(seconds: int | float) -> str:
    seconds = max(0, int(seconds))
    if seconds < 60:
        return f"{seconds}s"
    minutes, sec = divmod(seconds, 60)
    if minutes < 60:
        return f"{minutes}m {sec:02d}s"
    hours, minute = divmod(minutes, 60)
    if hours < 24:
        return f"{hours}h {minute:02d}m"
    days, hour = divmod(hours, 24)
    return f"{days}d {hour}h"


def proc_start_ticks(pid: int) -> int:
    try:
        # /proc/<pid>/stat field 22. The command field is enclosed in parentheses
        # and can contain spaces, so split only after the final ') '.
        raw = Path(f"/proc/{pid}/stat").read_text(encoding="utf-8", errors="replace")
        tail = raw.rsplit(") ", 1)[1].split()
        return int(tail[19])
    except Exception:
        return 0


def process_table() -> dict[int, dict]:
    ps = executable("ps")
    if not ps:
        return {}

    result = run(
        [
            ps,
            "-U",
            str(os.getuid()),
            "-o",
            "pid=,ppid=,pgid=,sid=,etimes=,pcpu=,rss=,comm=,args=",
        ],
        timeout=4.0,
    )
    if result.returncode != 0:
        return {}

    table: dict[int, dict] = {}
    for line in result.stdout.splitlines():
        parts = line.strip().split(None, 8)
        if len(parts) < 9:
            continue
        try:
            pid = int(parts[0])
            ppid = int(parts[1])
            pgid = int(parts[2])
            sid = int(parts[3])
            elapsed = int(parts[4])
            cpu = float(parts[5])
            rss = int(parts[6])
        except ValueError:
            continue
        if proc_uid(pid) != os.getuid():
            continue
        table[pid] = {
            "pid": pid,
            "ppid": ppid,
            "pgid": pgid,
            "sid": sid,
            "elapsed": elapsed,
            "cpu": cpu,
            "rss_kib": rss,
            "comm": parts[7],
            "args": parts[8],
            "start_ticks": proc_start_ticks(pid),
        }
    return table


def proc_cwd(pid: int) -> str:
    try:
        return os.readlink(f"/proc/{pid}/cwd")
    except OSError:
        return ""


def proc_uid(pid: int) -> int | None:
    try:
        return os.stat(f"/proc/{pid}").st_uid
    except OSError:
        return None


def display_path(path: str) -> str:
    if not path:
        return ""
    try:
        expanded = str(Path(path).expanduser())
        home = str(HOME)
        if expanded == home:
            return "~"
        prefix = home + os.sep
        if expanded.startswith(prefix):
            return "~/" + expanded[len(prefix):]
    except Exception:
        pass
    return path


def project_identity(path: str) -> str:
    if not path:
        return ""
    return hashlib.sha256(path.encode("utf-8", errors="replace")).hexdigest()[:16]


def project_root(cwd: str) -> str:
    if not cwd:
        return ""
    try:
        current = Path(cwd).resolve()
    except Exception:
        current = Path(cwd)
    if not current.exists():
        return cwd
    for candidate in (current, *current.parents):
        if str(candidate) in ("/", str(HOME)):
            break
        if any((candidate / marker).exists() for marker in PROJECT_MARKERS):
            return str(candidate)
    return cwd


def project_name(cwd: str) -> str:
    root = project_root(cwd)
    if not root:
        return ""
    name = Path(root).name
    # Don't surface the username merely because a daemon happens to have $HOME
    # as cwd. It is not a useful service identity.
    if Path(root) == HOME:
        return ""
    return name


def package_json(cwd: str) -> dict:
    root = project_root(cwd)
    if not root:
        return {}
    path = Path(root) / "package.json"
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def runtime_kind(program: str, cwd: str, args: str, port: int) -> str:
    if port in DB_PORTS:
        return DB_PORTS[port]

    lower = f"{program} {args}".lower()
    if program == "adb" or re.search(r"(^|[/\s])adb(?:\s|$)", lower):
        return "ADB"
    if "wayvnc" in lower:
        return "WayVNC"
    if "tailscaled" in lower:
        return "Tailscale"

    package = package_json(cwd)
    deps = {}
    deps.update(package.get("dependencies", {}) or {})
    deps.update(package.get("devDependencies", {}) or {})

    if (
        "next" in deps
        or "next-server" in lower
        or re.search(r"(^|[/\s])next(?:\s|$)", lower)
    ):
        return "Next.js"
    if "vite" in deps or re.search(r"(^|[/\s])vite(?:\s|$)", lower):
        return "Vite"
    if "astro" in deps or re.search(r"(^|[/\s])astro(?:\s|$)", lower):
        return "Astro"
    if "nuxt" in deps or re.search(r"(^|[/\s])nuxt(?:\s|$)", lower):
        return "Nuxt"
    if "uvicorn" in lower or "fastapi" in lower:
        return "FastAPI"
    if "django" in lower:
        return "Django"
    if "flask" in lower:
        return "Flask"
    if "python" in lower:
        return "Python"
    if "node" in lower or program in ("node", "bun"):
        return "Node.js"
    if "postgres" in lower:
        return "PostgreSQL"
    if "redis" in lower:
        return "Redis"
    return program or "Service"


def runtime_protocol(program: str, kind: str, args: str, port: int) -> str:
    lower = f"{program} {args}".lower()
    if kind in DB_PORTS.values():
        return "tcp"
    if kind == "ADB" or port == 5037:
        return "adb"
    if kind == "WayVNC" or "wayvnc" in lower:
        return "vnc"
    if kind == "Tailscale":
        return "tailscale"
    if re.search(r"(^|[/\s])sshd?(?:\s|$)", lower) or port == 22:
        return "ssh"
    if "https" in lower and kind in {"Next.js", "Vite", "Astro", "Nuxt", "FastAPI", "Django", "Flask", "Python", "Node.js"}:
        return "https"
    if (
        kind in {"Next.js", "Vite", "Astro", "Nuxt", "FastAPI", "Django", "Flask"}
        or "http.server" in lower
        or "serve" in lower
    ):
        return "http"
    return "tcp"


def runtime_name(cwd: str, program: str, kind: str) -> str:
    service_names = {
        "ADB": "ADB Server",
        "PostgreSQL": "PostgreSQL",
        "Redis": "Redis",
        "MySQL": "MySQL",
        "MongoDB": "MongoDB",
        "WayVNC": "WayVNC Remote Desktop",
        "Tailscale": "Tailscale",
    }
    if kind in service_names:
        return service_names[kind]
    project = project_name(cwd)
    if project and kind in {"Next.js", "Vite", "Astro", "Nuxt", "FastAPI", "Django", "Flask", "Node.js", "Python"}:
        return project
    return program or kind


def arch_remote_owner(program: str, port: int, args: str) -> dict:
    lower = f"{program} {args}".lower()

    # Ownership must be proven from the process identity, never inferred from a
    # convenient port. Port 8000 is common for Django/FastAPI and 5900 is a
    # generic VNC port.
    if (
        "wayvnc" in lower
        and "arch-remote.conf" in lower
        and port == 5900
    ):
        return {
            "managed": True,
            "name": "WayVNC Remote Desktop",
            "area": "Remote Desktop",
            "icon": "desktop_windows",
        }
    if port == 8000 and "lan-share/app.py" in lower:
        return {
            "managed": True,
            "name": "LAN Share",
            "area": "Private Share",
            "icon": "folder_shared",
        }
    return {"managed": False, "name": "", "area": "", "icon": ""}


def interface_addresses() -> dict[str, str]:
    ip = executable("ip")
    if not ip:
        return {}
    result = run([ip, "-j", "address", "show"], timeout=3.0)
    if result.returncode != 0:
        return {}
    try:
        payload = json.loads(result.stdout)
    except Exception:
        return {}
    mapping: dict[str, str] = {}
    for item in payload:
        name = str(item.get("ifname", ""))
        for addr in item.get("addr_info", []) or []:
            local = str(addr.get("local", ""))
            if local:
                mapping[local] = name
    return mapping


def classify_bind(address: str, interfaces: dict[str, str]) -> tuple[str, bool]:
    if address in ("127.0.0.1", "::1", "localhost"):
        return "Local", False
    if address in ("0.0.0.0", "::", "*"):
        return "All interfaces", True

    iface = interfaces.get(address, "")
    if iface.startswith("tailscale"):
        return "Tailscale", True

    try:
        ip = ipaddress.ip_address(address.split("%", 1)[0])
    except ValueError:
        return "Bound", True

    if ip.is_loopback:
        return "Local", False
    if ip.version == 4 and ip in ipaddress.ip_network("100.64.0.0/10"):
        return ("Tailscale" if iface.startswith("tailscale") else "Private"), True
    if ip.is_private or ip.is_link_local:
        return "LAN", True
    return "Public", True


def runtime_pin_key(program: str, cwd: str, kind: str, port: int, address: str) -> str:
    material = "\0".join((program, project_root(cwd), kind, str(port), address)).encode("utf-8", errors="replace")
    return hashlib.sha256(material).hexdigest()[:20]



def proc_comm(pid: int) -> str:
    try:
        return Path(f"/proc/{pid}/comm").read_text(
            encoding="utf-8",
            errors="replace",
        ).strip()
    except OSError:
        return ""


def _ss_inline_owners(line: str) -> list[tuple[str, int]]:
    """Extract all process owners from ss users:(...) metadata.

    iproute2 may truncate comm names or emit multiple owner tuples. Keep this
    parser deliberately loose around fd/extra fields and validate ownership
    against /proc separately.
    """
    owners: list[tuple[str, int]] = []
    seen: set[int] = set()
    for match in re.finditer(
        r'"([^"]+)"[^)]*?\bpid=(\d+)(?:,|\))',
        line,
    ):
        try:
            pid = int(match.group(2))
        except ValueError:
            continue
        if pid in seen:
            continue
        seen.add(pid)
        owners.append((match.group(1), pid))
    return owners


def _socket_inode_owners() -> dict[int, list[int]]:
    """Map TCP socket inode -> current-user PID(s) from /proc.

    This is a fallback for service/sandbox contexts where `ss -p` can expose
    the listener and inode but omit users:(...) process metadata.
    """
    uid = os.getuid()
    mapping: dict[int, list[int]] = {}
    proc_root = Path("/proc")

    for entry in proc_root.iterdir():
        if not entry.name.isdigit():
            continue
        pid = int(entry.name)
        try:
            if entry.stat().st_uid != uid:
                continue
            fd_dir = entry / "fd"
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if not match:
                    continue
                inode = int(match.group(1))
                bucket = mapping.setdefault(inode, [])
                if pid not in bucket:
                    bucket.append(pid)
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue

    return mapping


def _decode_proc_net_address(value: str, ipv6: bool) -> str:
    """Decode /proc/net/tcp{,6} hexadecimal address format."""
    raw = bytes.fromhex(value)
    if ipv6:
        if len(raw) != 16:
            raise ValueError("invalid tcp6 address")
        # Linux renders each 32-bit word in host byte order.
        raw = b"".join(raw[index:index + 4][::-1] for index in range(0, 16, 4))
        return socket.inet_ntop(socket.AF_INET6, raw)
    if len(raw) != 4:
        raise ValueError("invalid tcp address")
    return socket.inet_ntop(socket.AF_INET, raw[::-1])


def _proc_tcp_listeners() -> list[tuple[str, int, int]]:
    """Return current-user LISTEN sockets as (address, port, inode).

    /proc/net/tcp is used as a kernel-level fallback because `ss -p` owner
    metadata is not guaranteed to be available from every long-running user
    service context. Ownership is still proven by both the socket uid and the
    inode -> /proc/<pid>/fd mapping before a runtime is emitted.
    """
    uid = os.getuid()
    listeners: list[tuple[str, int, int]] = []
    seen: set[tuple[str, int, int]] = set()

    for path, ipv6 in ((Path("/proc/net/tcp"), False), (Path("/proc/net/tcp6"), True)):
        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()[1:]
        except OSError:
            continue

        for line in lines:
            parts = line.split()
            if len(parts) < 10 or parts[3] != "0A":
                continue
            try:
                address_hex, port_hex = parts[1].rsplit(":", 1)
                socket_uid = int(parts[7])
                inode = int(parts[9])
                if socket_uid != uid or inode <= 0:
                    continue
                address = _decode_proc_net_address(address_hex, ipv6)
                port = int(port_hex, 16)
            except (ValueError, IndexError):
                continue

            item = (address, port, inode)
            if item not in seen:
                seen.add(item)
                listeners.append(item)

    return listeners


def _ss_owners(
    line: str,
    table: dict[int, dict],
    inode_cache: dict | None = None,
) -> tuple[list[tuple[str, int]], dict | None]:
    inline = [
        (program, pid)
        for program, pid in _ss_inline_owners(line)
        if proc_uid(pid) == os.getuid()
    ]
    if inline:
        return inline, inode_cache

    # `ss -e` adds uid:<n> and ino:<n>. If users:(...) is unavailable, only
    # consider sockets explicitly owned by this user, then resolve the inode
    # through /proc/<pid>/fd.
    uid_match = re.search(r"\buid:(\d+)\b", line)
    inode_match = re.search(r"\bino:(\d+)\b", line)
    if not uid_match or not inode_match:
        return [], inode_cache
    if int(uid_match.group(1)) != os.getuid():
        return [], inode_cache

    inode = int(inode_match.group(1))
    if inode_cache is None:
        inode_cache = _socket_inode_owners()

    owners: list[tuple[str, int]] = []
    for pid in inode_cache.get(inode, []):
        if proc_uid(pid) != os.getuid():
            continue
        info = table.get(pid, {})
        program = str(info.get("comm", "")).strip() or proc_comm(pid) or f"pid-{pid}"
        owners.append((program, pid))
    return owners, inode_cache


def parse_ss(table: dict[int, dict]) -> list[dict]:
    ss = executable("ss")
    interfaces = interface_addresses()
    config = load_config()
    entries: list[dict] = []
    seen: set[tuple[int, int, str]] = set()
    inode_cache: dict[int, list[int]] | None = None

    def add_entry(program: str, pid: int, address: str, port: int) -> None:
        key_tuple = (pid, port, address)
        if key_tuple in seen:
            return
        if proc_uid(pid) != os.getuid():
            return
        seen.add(key_tuple)

        info = table.get(pid, {
            "pid": pid,
            "elapsed": 0,
            "cpu": 0.0,
            "rss_kib": 0,
            "args": program,
            "comm": program,
            "start_ticks": proc_start_ticks(pid),
        })
        cwd = proc_cwd(pid)
        args = str(info.get("args", ""))
        effective_program = str(info.get("comm", "")).strip() or program or proc_comm(pid)
        if runtime_ignored(config, effective_program, args, port):
            return
        detector = matching_detector(config, effective_program, args, cwd, port)
        kind = detector.get("kind") or runtime_kind(effective_program, cwd, args, port)
        protocol = detector.get("protocol") or runtime_protocol(effective_program, kind, args, port)
        scope, exposed = classify_bind(address, interfaces)
        remote_owner = arch_remote_owner(effective_program, port, args)
        display_name = (
            remote_owner["name"]
            if remote_owner["managed"]
            else (detector.get("name") or runtime_name(cwd, effective_program, kind))
        )
        icon = detector.get("icon") or (
            remote_owner["icon"]
            if remote_owner["managed"]
            else ("public" if exposed else "dns")
        )
        start_ticks = int(info.get("start_ticks", 0))
        url = ""
        if protocol in ("http", "https"):
            url = f"{protocol}://localhost:{port}"
        pin_key = runtime_pin_key(
            effective_program,
            cwd,
            kind,
            port,
            address,
        )
        entries.append({
            "key": f"{pid}:{start_ticks}:{port}:{address}",
            "pin_key": pin_key,
            "name": display_name,
            "kind": kind,
            "protocol": protocol,
            "pid": pid,
            "start_ticks": start_ticks,
            "port": port,
            "address": address,
            "bind": f"{address}:{port}",
            "url": url,
            "endpoint": url if url else f"{address}:{port}",
            "icon": icon,
            "cwd": display_path(cwd),
            "cpu": round(float(info.get("cpu", 0.0)), 1),
            "memory": human_bytes(int(info.get("rss_kib", 0))),
            "memory_kib": int(info.get("rss_kib", 0)),
            "uptime": human_seconds(int(info.get("elapsed", 0))),
            "elapsed": int(info.get("elapsed", 0)),
            "scope": scope,
            "exposed": exposed,
            "status": "Listening",
            "managed_by_arch_remote": remote_owner["managed"],
            "managed_area": remote_owner["area"],
            "managed_icon": remote_owner["icon"],
            "operations_stop_allowed": not remote_owner["managed"],
        })

    # Fast path: ask ss for owners. `-e` also exposes uid/inode metadata, which
    # lets _ss_owners recover ownership when users:(...) is omitted.
    if ss:
        result = run([ss, "-H", "-ltnpe"], timeout=4.0)
        if result.returncode != 0:
            result = run([ss, "-H", "-ltnp"], timeout=4.0)

        if result.returncode == 0:
            for line in result.stdout.splitlines():
                columns = line.split()
                if len(columns) < 4:
                    continue
                local = columns[3]
                if local.startswith("["):
                    match = re.match(r"^\[(.*)\]:(\d+)$", local)
                else:
                    match = re.match(r"^(.*):(\d+)$", local)
                if not match:
                    continue
                address = match.group(1)
                port = int(match.group(2))

                owners, inode_cache = _ss_owners(line, table, inode_cache)
                for program, pid in owners:
                    add_entry(program, pid, address, port)

    # Kernel fallback: /proc/net/tcp{,6} exposes LISTEN socket uid+inode without
    # relying on ss process metadata. Map each current-user inode back to a
    # current-user PID through /proc/<pid>/fd. This is the authoritative repair
    # for systemd/service contexts where the ss fast path returns no owners.
    proc_listeners = _proc_tcp_listeners()
    if proc_listeners:
        if inode_cache is None:
            inode_cache = _socket_inode_owners()
        for address, port, inode in proc_listeners:
            for pid in inode_cache.get(inode, []):
                if proc_uid(pid) != os.getuid():
                    continue
                info = table.get(pid, {})
                program = (
                    str(info.get("comm", "")).strip()
                    or proc_comm(pid)
                    or f"pid-{pid}"
                )
                add_entry(program, pid, address, port)

    return entries


def _command_has(regex: str, command: str) -> bool:
    return re.search(regex, command, re.IGNORECASE) is not None


def _job_kinds(command: str) -> list[str]:
    lower = command.lower().strip()
    if not lower:
        return []

    # Read-only update probes are telemetry, not user operations.
    if "checkup-db-" in lower or "checkupdates" in lower or re.search(r"\bpacman\s+-qu\b", lower):
        return []

    # Next.js embeds jest-worker for general parallelism; that is not evidence
    # of a test run.
    if "next/dist/compiled/jest-worker" in lower or "jest-worker/processchild" in lower:
        return []

    kinds: list[str] = []

    def add(kind: str, matched: bool) -> None:
        if matched and kind not in kinds:
            kinds.append(kind)

    # Quotes are valid left boundaries inside shell wrapper command strings.
    boundary = r"(?:^|[/\s'\"])"

    add("Build", bool(
        _command_has(boundary + r"pnpm(?:\s+run)?\s+build(?:[:\w.-]*)?\b", lower)
        or _command_has(boundary + r"npm\s+run\s+build(?:[:\w.-]*)?\b", lower)
        or _command_has(boundary + r"(?:yarn|bun)(?:\s+run)?\s+build(?:[:\w.-]*)?\b", lower)
        or _command_has(boundary + r"(?:next|vite|astro|nuxt)\s+build\b", lower)
        or _command_has(boundary + r"cargo\s+build\b|" + boundary + r"cmake\s+--build\b|" + boundary + r"ninja(?:\s|$)|" + boundary + r"make(?:\s|$)", lower)
    ))
    add("Tests", bool(
        _command_has(boundary + r"pnpm(?:\s+run)?\s+test(?:[:\w.-]*)?\b", lower)
        or _command_has(boundary + r"npm(?:\s+run)?\s+test(?:[:\w.-]*)?\b", lower)
        or _command_has(boundary + r"(?:yarn|bun)(?:\s+run)?\s+test(?:[:\w.-]*)?\b", lower)
        or _command_has(boundary + r"(?:vitest|jest|pytest)(?:\s|$)", lower)
        or _command_has(boundary + r"cargo\s+test\b", lower)
    ))
    add("Packages", bool(_command_has(boundary + r"(?:paru|yay)(?:\s|$)|" + boundary + r"pacman(?:\s|$)", lower)))
    add("Media", bool(_command_has(boundary + r"(?:ffmpeg|ffprobe)(?:\s|$)", lower)))
    add("Transfer", bool(_command_has(boundary + r"(?:rsync|wget|curl)(?:\s|$)", lower)))
    add("Agent", bool(_command_has(boundary + r"(?:codex|opencode)(?:\s|$)", lower)))
    return kinds


def classify_job(command: str, comm: str = "") -> dict:
    kinds = _job_kinds(command)
    if not kinds:
        return {"kind": "", "wrapper": False, "kinds": []}

    lower = command.lower().strip()
    shell = comm.lower() in {"sh", "bash", "dash", "zsh", "fish"}
    shell_boundary = r"(?:^|[/\s'\"])"
    shell_command = shell and re.search(shell_boundary + r"(?:sh|bash|dash|zsh|fish)\s+-c(?:\s|$)", lower) is not None
    has_sequence = shell_command and any(token in lower for token in ("&&", "||", ";", "\n"))

    # A persistent shell wrapper is the best operation boundary for sequential
    # workflows. It stays alive while individual build/test/package children
    # come and go, preventing each phase from becoming a separate operation.
    wrapper = bool(shell_command and (has_sequence or len(kinds) > 1))
    kind = kinds[0] if len(kinds) == 1 else "Workflow"
    return {"kind": kind, "wrapper": wrapper, "kinds": kinds}

def identify_job(command: str, comm: str = "") -> str:
    return str(classify_job(command, comm).get("kind", ""))


def ancestor_chain(pid: int, table: dict[int, dict], limit: int = 64) -> list[int]:
    result = []
    seen = set()
    current = pid
    for _ in range(limit):
        info = table.get(current)
        if not info:
            break
        parent = int(info.get("ppid", 0))
        if parent <= 1 or parent in seen:
            break
        result.append(parent)
        seen.add(parent)
        current = parent
    return result


def _process_context(pid: int, table: dict[int, dict], cwd_cache: dict[int, str], project_cache: dict[int, str]) -> tuple[str, str]:
    if pid not in cwd_cache:
        cwd_cache[pid] = proc_cwd(pid)
    if pid not in project_cache:
        project_cache[pid] = project_root(cwd_cache[pid])
    return cwd_cache[pid], project_cache[pid]


def _compatible_operation_ancestor(
    child_pid: int,
    ancestor_pid: int,
    candidates: dict[int, dict],
    table: dict[int, dict],
    cwd_cache: dict[int, str],
    project_cache: dict[int, str],
) -> bool:
    child = candidates[child_pid]
    ancestor = candidates[ancestor_pid]
    _, child_project = _process_context(child_pid, table, cwd_cache, project_cache)
    _, ancestor_project = _process_context(ancestor_pid, table, cwd_cache, project_cache)

    # Do not merge two known, different projects merely because one happened to
    # launch the other. Empty project roots are allowed because package/media
    # commands frequently run outside a source tree.
    if child_project and ancestor_project and child_project != ancestor_project:
        return False

    if ancestor.get("wrapper"):
        return True
    return ancestor.get("kind") == child.get("kind")


def operation_roots(table: dict[int, dict], runtime_pids: set[int]) -> tuple[dict[int, int], dict[int, dict]]:
    candidates: dict[int, dict] = {}
    for pid, info in table.items():
        if pid in runtime_pids:
            continue
        classified = classify_job(str(info.get("args", "")), str(info.get("comm", "")))
        if classified.get("kind"):
            candidates[pid] = classified

    cwd_cache: dict[int, str] = {}
    project_cache: dict[int, str] = {}
    roots: dict[int, int] = {}
    for pid in candidates:
        root = pid
        # Walk nearest -> oldest. Any compatible shell workflow ancestor owns
        # the whole workflow; otherwise same-kind ancestors collapse nested
        # wrappers such as pnpm -> next/build workers.
        for ancestor in ancestor_chain(pid, table):
            if ancestor not in candidates:
                continue
            if _compatible_operation_ancestor(pid, ancestor, candidates, table, cwd_cache, project_cache):
                root = ancestor
        roots[pid] = root
    return roots, candidates


def discover_operations(table: dict[int, dict], runtime_pids: set[int]) -> list[dict]:
    candidate_roots, candidates = operation_roots(table, runtime_pids)
    if not candidate_roots:
        return []

    unique_roots = set(candidate_roots.values())
    members: dict[int, list[int]] = {pid: [] for pid in unique_roots}

    # A process belongs to the nearest classified ancestor, then to that
    # candidate's resolved logical root. This lets an Agent launch an independent
    # Build, while a classified shell workflow owns all of its build/test phases.
    for pid in table:
        lineage = [pid, *ancestor_chain(pid, table)]
        nearest_candidate = next((ancestor for ancestor in lineage if ancestor in candidate_roots), None)
        if nearest_candidate is None:
            continue
        logical_root = candidate_roots[nearest_candidate]
        members.setdefault(logical_root, []).append(pid)

    now = time.time()
    operations: list[dict] = []
    for root_pid in unique_roots:
        root_info = table.get(root_pid)
        root_class = candidates.get(root_pid)
        if not root_info or not root_class:
            continue

        filtered_members = sorted(set(members.get(root_pid, [root_pid])))
        if root_pid not in filtered_members:
            filtered_members.insert(0, root_pid)

        cwd = proc_cwd(root_pid)
        root_project = project_root(cwd)
        pname = project_name(cwd)
        cpu = round(sum(float(table[p].get("cpu", 0.0)) for p in filtered_members if p in table), 1)
        memory_kib = sum(int(table[p].get("rss_kib", 0)) for p in filtered_members if p in table)
        elapsed = max((int(table[p].get("elapsed", 0)) for p in filtered_members if p in table), default=int(root_info.get("elapsed", 0)))
        start_ticks = int(root_info.get("start_ticks", 0))
        pgid = int(root_info.get("pgid", 0) or 0)
        sid = int(root_info.get("sid", 0) or 0)
        key = f"{root_pid}:{start_ticks}"
        display_name = (
            " + ".join(str(item) for item in root_class.get("kinds", []) if item)
            if root_class.get("kind") == "Workflow"
            else str(root_class.get("kind", "Operation"))
        ) or "Workflow"
        operations.append({
            "key": key,
            "operation_id": key,
            "root_pid": root_pid,
            "root_start_ticks": start_ticks,
            "pid": root_pid,
            "pgid": pgid,
            "sid": sid,
            "name": display_name,
            "kind": str(root_class.get("kind", "Operation")),
            "component_kinds": list(root_class.get("kinds", [])),
            "workflow_wrapper": bool(root_class.get("wrapper")),
            "project": pname,
            "project_key": project_identity(root_project),
            "elapsed": elapsed,
            "uptime": human_seconds(elapsed),
            "started_at": now - elapsed,
            "cpu": cpu,
            "memory": human_bytes(memory_kib),
            "memory_kib": memory_kib,
            "process_count": len(filtered_members),
            "status": "Running",
            "outcome": "running",
            "last_seen_at": now,
        })

    operations.sort(key=lambda item: (-int(item.get("elapsed", 0)), item.get("kind", ""), item.get("project", "")))
    return operations


def _continuity_signature(item: dict) -> tuple:
    return (
        int(item.get("sid", 0) or 0),
        int(item.get("pgid", 0) or 0),
        str(item.get("project_key", "")),
        str(item.get("kind", "")),
    )


def reconcile_operation_continuity(current: list[dict], previous: list[dict], now: float) -> list[dict]:
    # Normally root PID+start_ticks is stable. If a supervisor/root exits before
    # its same-process-group child, preserve operation identity across the handoff
    # rather than creating a second history row. SID/PGID are used only as this
    # short-lived continuity fallback, never to globally merge unrelated jobs.
    previous_by_key = {str(item.get("key", "")): item for item in previous if item.get("key")}
    unmatched_previous = {str(item.get("key", "")): item for item in previous if item.get("key")}
    reconciled: list[dict] = []

    for item in current:
        row = dict(item)
        direct = previous_by_key.get(str(row.get("key", "")))
        matched = direct

        if matched is None:
            signature = _continuity_signature(row)
            if signature[0] > 1 and signature[1] > 1:
                options = [
                    old for old in unmatched_previous.values()
                    if _continuity_signature(old) == signature
                    and max(0.0, now - float(old.get("last_seen_at", now))) <= MONITOR_FRESH_SECONDS
                ]
                if len(options) == 1:
                    matched = options[0]

        if matched is not None:
            old_key = str(matched.get("key", ""))
            unmatched_previous.pop(old_key, None)
            stable_id = str(matched.get("operation_id") or matched.get("key") or row.get("key"))
            row["key"] = stable_id
            row["operation_id"] = stable_id
            row["started_at"] = min(
                float(matched.get("started_at", row.get("started_at", now)) or now),
                float(row.get("started_at", now) or now),
            )
            if matched.get("workflow_wrapper"):
                # Bash may exec() the final command of a sequence into the same
                # PID. Preserve the wrapper's logical identity and original
                # command rather than degrading Workflow -> Build/Test at the
                # last phase.
                row["kind"] = str(matched.get("kind", row.get("kind", "Workflow")))
                row["name"] = str(matched.get("name", row.get("name", "Workflow")))
                row["component_kinds"] = list(matched.get("component_kinds", row.get("component_kinds", [])))
                row["workflow_wrapper"] = True
            row["elapsed"] = max(0, int(now - float(row["started_at"])))
            row["uptime"] = human_seconds(row["elapsed"])
        reconciled.append(row)

    return reconciled


def _history_record(old: dict, now: float, previous_scan_at: float) -> dict:
    ended = sanitize_history_record(old)
    last_seen = float(old.get("last_seen_at", previous_scan_at or now))
    gap = max(0.0, now - last_seen)
    ended["status"] = "Ended"
    ended["outcome"] = "unknown"
    ended["ended_at"] = now
    ended["last_seen_at"] = last_seen
    ended["end_observation_gap"] = round(gap, 3)
    ended["end_time_precision"] = "observed" if gap <= MONITOR_FRESH_SECONDS else "after-monitor-gap"
    ended["result_label"] = "Result unknown"
    return ended


def monitor_once() -> dict:
    table = process_table()
    runtimes = parse_ss(table)
    runtime_pids = {int(item["pid"]) for item in runtimes}
    discovered = discover_operations(table, runtime_pids)
    now = time.time()
    previous_live = load_json(LIVE_PATH, {})
    if int(previous_live.get("schema_version", 0) or 0) != SCHEMA_VERSION:
        previous_live = {}
    previous_list = [item for item in previous_live.get("operations", []) if isinstance(item, dict)]
    operations = reconcile_operation_continuity(discovered, previous_list, now)

    previous_operations = {
        str(item.get("operation_id") or item.get("key", "")): item
        for item in previous_list
        if item.get("operation_id") or item.get("key")
    }
    current_keys = {str(item.get("operation_id") or item.get("key")) for item in operations}
    previous_scan_at = float(previous_live.get("timestamp", 0.0) or 0.0)
    ended_records = [
        _history_record(old, now, previous_scan_at)
        for key, old in previous_operations.items()
        if key not in current_keys
    ]

    if ended_records:
        with locked_state() as app_state:
            history = list(app_state.get("operation_history", []))
            existing = {str(item.get("operation_id") or item.get("key", "")) for item in history}
            for ended in ended_records:
                history_key = str(ended.get("operation_id") or ended.get("key", ""))
                if history_key and history_key not in existing:
                    history.insert(0, ended)
                    existing.add(history_key)
            app_state["operation_history"] = history[:HISTORY_LIMIT]
            save_state(app_state)

    live_payload = {
        "schema_version": SCHEMA_VERSION,
        "ui_contract": UI_CONTRACT,
        "backend_revision": BACKEND_REVISION,
        "timestamp": now,
        "runtimes": runtimes,
        "operations": operations,
    }
    atomic_json(LIVE_PATH, live_payload)
    return live_payload


def monitor_forever() -> int:
    LIVE_DIR.mkdir(parents=True, exist_ok=True)
    while True:
        started = time.monotonic()
        try:
            monitor_once()
        except Exception as error:
            previous = load_json(LIVE_PATH, {})
            atomic_json(LIVE_PATH, {
                "schema_version": SCHEMA_VERSION,
                "ui_contract": UI_CONTRACT,
                "backend_revision": BACKEND_REVISION,
                "timestamp": time.time(),
                "runtimes": list(previous.get("runtimes", [])) if isinstance(previous, dict) else [],
                "operations": list(previous.get("operations", [])) if isinstance(previous, dict) else [],
                "monitor_error": str(error),
            })
        elapsed = time.monotonic() - started
        time.sleep(max(0.25, MONITOR_INTERVAL - elapsed))


def recent_history(limit: int = 20) -> list[dict]:
    items = list(state().get("operation_history", []))[:limit]
    now = time.time()
    result = []
    for item in items:
        row = dict(item)
        ended_at = float(row.get("ended_at", 0.0) or 0.0)
        last_seen = float(row.get("last_seen_at", 0.0) or 0.0)
        if row.get("end_time_precision") == "after-monitor-gap" and last_seen:
            row["time_label"] = f"Last seen {human_seconds(max(0, now - last_seen))} ago"
        elif ended_at:
            row["time_label"] = f"Ended {human_seconds(max(0, now - ended_at))} ago"
        else:
            row["time_label"] = "Ended"
        result.append(row)
    return result


def group_active_jobs(items: list[dict]) -> list[dict]:
    # Compatibility contract for the QML view: each row is now one logical
    # operation rather than a bucket of unrelated matching PIDs.
    return [dict(item) for item in items]


def group_job_history(items: list[dict]) -> list[dict]:
    # Kept for older clients; v3 UI uses job_history directly.
    return [dict(item) for item in items[:8]]


def failed_user_units() -> list[str]:
    systemctl = executable("systemctl")
    if not systemctl:
        return []
    result = run([systemctl, "--user", "--failed", "--no-legend", "--plain"], timeout=3.0)
    if result.returncode not in (0, 1):
        return []
    units = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if line:
            units.append(line.split()[0])
    return units[:8]


def disk_info() -> dict:
    usage = shutil.disk_usage("/")
    percent = (usage.used / usage.total) * 100.0 if usage.total else 0.0
    return {
        "percent": round(percent, 1),
        "free": human_bytes(usage.free / 1024.0),
        "used": human_bytes(usage.used / 1024.0),
        "total": human_bytes(usage.total / 1024.0),
    }


def memory_info() -> dict:
    values = {}
    try:
        for line in Path("/proc/meminfo").read_text().splitlines():
            key, rest = line.split(":", 1)
            values[key] = int(rest.strip().split()[0])
    except Exception:
        return {"percent": 0, "used": "—", "total": "—"}
    total = values.get("MemTotal", 0)
    available = values.get("MemAvailable", 0)
    used = max(0, total - available)
    percent = (used / total * 100.0) if total else 0.0
    return {
        "percent": round(percent, 1),
        "used": human_bytes(used),
        "total": human_bytes(total),
    }


def load_info() -> str:
    try:
        one, five, fifteen = os.getloadavg()
        return f"{one:.2f} · {five:.2f} · {fifteen:.2f}"
    except Exception:
        return "—"


def hypr_config_errors() -> list[str]:
    hyprctl = executable("hyprctl")
    if not hyprctl:
        return []
    result = run([hyprctl, "configerrors"], timeout=3.0)
    if result.returncode != 0:
        return []
    return [line.strip() for line in result.stdout.splitlines() if line.strip()][:8]


def _slow_attention() -> list[dict]:
    cached = load_json(ATTENTION_CACHE_PATH, {})
    now = time.time()
    if (
        isinstance(cached, dict)
        and now - float(cached.get("timestamp", 0.0) or 0.0) < ATTENTION_CACHE_SECONDS
        and isinstance(cached.get("items"), list)
    ):
        return list(cached["items"])

    result: list[dict] = []
    config_errors = hypr_config_errors()
    if config_errors:
        result.append({
            "severity": "critical",
            "icon": "error",
            "title": "Hyprland config errors",
            "detail": config_errors[0],
        })

    failed = failed_user_units()
    if failed:
        result.append({
            "severity": "critical",
            "icon": "error",
            "title": f"{len(failed)} failed user service(s)",
            "detail": ", ".join(failed[:3]),
        })

    disk = disk_info()
    if disk["percent"] >= 90:
        result.append({
            "severity": "critical",
            "icon": "storage",
            "title": "Disk space is critically low",
            "detail": f"{disk['percent']}% used · {disk['free']} free",
        })
    elif disk["percent"] >= 80:
        result.append({
            "severity": "warning",
            "icon": "storage",
            "title": "Disk space is getting low",
            "detail": f"{disk['percent']}% used · {disk['free']} free",
        })

    atomic_json(ATTENTION_CACHE_PATH, {
        "schema_version": SCHEMA_VERSION,
        "timestamp": now,
        "items": result,
    })
    return result


def fast_attention(
    runtimes: list[dict],
    monitor_fresh: bool = True,
    monitor_error: str = "",
) -> list[dict]:
    result = _slow_attention()

    exposed = [
        item for item in runtimes
        if item.get("exposed") and not item.get("managed_by_arch_remote")
    ]
    if exposed:
        details = ", ".join(
            f"{item.get('scope', 'Bound')} :{item['port']}"
            for item in exposed[:5]
        )
        result.append({
            "severity": "info",
            "icon": "public",
            "title": "Services reachable beyond localhost",
            "detail": details,
        })

    if not monitor_fresh:
        detail = monitor_error or (
            "Background operation tracking is not fresh; history may be incomplete."
        )
        result.append({
            "severity": "warning",
            "icon": "history_toggle_off",
            "title": "Operations monitor is not active",
            "detail": detail,
        })
    return result


def package_updates() -> dict:
    official: list[str] = []
    aur: list[str] = []
    official_known = False
    aur_known = False
    official_source = ""
    aur_source = ""

    checkupdates = executable("checkupdates")
    if checkupdates:
        result = run([checkupdates], timeout=10.0)
        if result.returncode in (0, 2):
            official = [line for line in result.stdout.splitlines() if line.strip()]
            official_known = True
            official_source = "checkupdates"
    else:
        pacman = executable("pacman")
        if pacman:
            result = run([pacman, "-Qu"], timeout=6.0)
            if result.returncode in (0, 1):
                official = [line for line in result.stdout.splitlines() if line.strip()]
                official_known = True
                official_source = "pacman -Qu"

    paru = executable("paru")
    if paru:
        result = run([paru, "-Qua"], timeout=8.0)
        if result.returncode in (0, 1):
            aur = [line for line in result.stdout.splitlines() if line.strip()]
            aur_known = True
            aur_source = "paru -Qua"

    total = len(official) + len(aur) if official_known and aur_known else -1
    return {
        "official": official[:80],
        "aur": aur[:80],
        "official_count": len(official) if official_known else -1,
        "aur_count": len(aur) if aur_known else -1,
        "total": total,
        "official_known": official_known,
        "aur_known": aur_known,
        "official_source": official_source,
        "aur_source": aur_source,
        "source": " + ".join(item for item in (official_source, aur_source) if item),
    }


def system_snapshot(force=False) -> dict:
    cached = load_json(SYSTEM_CACHE_PATH, {})
    now = time.time()
    update_cached_at = float(
        cached.get("updates_cached_at", cached.get("_cached_at", 0)) or 0
    )
    updates = cached.get("updates", {}) if isinstance(cached.get("updates"), dict) else {}
    if force or not updates or now - update_cached_at >= 600:
        updates = package_updates()
        update_cached_at = now

    failed = failed_user_units()
    disk = disk_info()
    memory = memory_info()
    payload = {
        "schema_version": SCHEMA_VERSION,
        "ui_contract": UI_CONTRACT,
        "backend_revision": BACKEND_REVISION,
        "_cached_at": now,
        "updates_cached_at": update_cached_at,
        "updates": updates,
        "failed_units": failed,
        "failed_unit_count": len(failed),
        "disk": disk,
        "memory": memory,
        "load": load_info(),
        "hostname": socket.gethostname(),
    }
    atomic_json(SYSTEM_CACHE_PATH, payload)
    return payload


def snapshot() -> dict:
    now = time.time()
    live = load_json(LIVE_PATH, {})
    live_schema_ok = int(live.get("schema_version", 0) or 0) == SCHEMA_VERSION
    monitor_age = (
        max(0.0, now - float(live.get("timestamp", 0.0) or 0.0))
        if live
        else 10**9
    )
    monitor_fresh = (
        bool(live)
        and live_schema_ok
        and monitor_age <= MONITOR_FRESH_SECONDS
        and not live.get("monitor_error")
    )

    if monitor_fresh:
        runtimes = [dict(item) for item in live.get("runtimes", []) if isinstance(item, dict)]
        operations = [dict(item) for item in live.get("operations", []) if isinstance(item, dict)]
    else:
        table = process_table()
        runtimes = parse_ss(table)
        runtime_pids = {int(item["pid"]) for item in runtimes}
        operations = discover_operations(table, runtime_pids)

    app_state = state()
    pins = set(str(item) for item in app_state.get("pinned_runtime_keys", []))
    for runtime in runtimes:
        runtime["pinned"] = runtime.get("pin_key") in pins
    runtimes.sort(
        key=lambda item: (not item.get("pinned", False), item.get("port", 0), str(item.get("name", "")).lower())
    )

    history = recent_history(20)
    job_groups = group_active_jobs(operations)
    history_groups = group_job_history(history)
    attention = fast_attention(
        runtimes,
        monitor_fresh=monitor_fresh,
        monitor_error=str(live.get("monitor_error", "")),
    )
    cached_system = load_json(SYSTEM_CACHE_PATH, {})
    updates = cached_system.get("updates", {}) if isinstance(cached_system, dict) else {}
    update_count = int(updates.get("total", -1)) if updates else -1
    if update_count > 0:
        official = int(updates.get("official_count", -1))
        aur = int(updates.get("aur_count", -1))
        parts = []
        if official >= 0:
            parts.append(f"{official} official")
        if aur >= 0:
            parts.append(f"{aur} AUR")
        attention.append({
            "severity": "maintenance",
            "icon": "system_update",
            "title": f"{update_count} package update(s) available",
            "detail": " · ".join(parts) if parts else "Package updates available",
        })

    tracked_process_count = sum(
        int(item.get("process_count", 1)) for item in operations
    )
    return {
        "schema_version": SCHEMA_VERSION,
        "ui_contract": UI_CONTRACT,
        "backend_revision": BACKEND_REVISION,
        "timestamp": now,
        "monitor": {
            "active": monitor_fresh,
            "age_seconds": round(monitor_age, 1) if monitor_age < 10**8 else -1,
            "interval_seconds": MONITOR_INTERVAL,
            "error": str(live.get("monitor_error", "")),
        },
        "runtimes": runtimes,
        "jobs": operations,
        "job_groups": job_groups,
        "job_history": history,
        "history_groups": history_groups,
        "attention": attention,
        "summary": {
            "runtime_count": len(runtimes),
            "local_runtime_count": sum(
                1 for item in runtimes if not item.get("managed_by_arch_remote")
            ),
            "remote_managed_count": sum(
                1 for item in runtimes if item.get("managed_by_arch_remote")
            ),
            "job_count": len(operations),
            "operation_count": len(operations),
            "tracked_process_count": tracked_process_count,
            "job_group_count": len(operations),
            "attention_count": len([
                item for item in attention
                if item.get("severity") in ("critical", "warning")
            ]),
            "maintenance_count": len([
                item for item in attention if item.get("severity") == "maintenance"
            ]),
            "update_count": update_count,
        },
    }


def ensure_safe_process(pid: int, expected_start_ticks: int = 0) -> dict:
    if pid <= 1:
        raise ValueError("refusing unsafe PID")
    uid = proc_uid(pid)
    if uid is None:
        raise ValueError("process no longer exists")
    if uid != os.getuid():
        raise ValueError("process is not owned by the current user")
    actual_start = proc_start_ticks(pid)
    if expected_start_ticks and actual_start != expected_start_ticks:
        raise ValueError("process identity changed; refusing stale PID action")
    try:
        command = Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace")
    except Exception:
        command = ""
    shell_pattern = (
        r"(^|\s)(qs|quickshell)\s+-c\s+"
        + re.escape(QS_CONFIG)
        + r"(?:\s|$)"
    )
    if re.search(shell_pattern, command):
        raise ValueError("refusing to stop the active Quickshell process")
    return {"pid": pid, "start_ticks": actual_start, "command": command}


def open_url(url: str) -> dict:
    if not re.match(r"^https?://(?:localhost|127\.0\.0\.1|\[::1\])(?::\d+)?(?:/.*)?$", url):
        raise ValueError("only verified local HTTP(S) URLs can be opened")
    xdg_open = executable("xdg-open")
    if not xdg_open:
        raise ValueError("xdg-open is unavailable")
    subprocess.Popen([xdg_open, url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    return {"ok": True, "message": f"Opened {url}"}


def terminal_command() -> list[str]:
    config_command = configured_command("terminal")
    if config_command:
        return config_command
    configured = (
        os.environ.get("OPERATIONS_CENTER_TERMINAL")
        or os.environ.get("TERMINAL")
        or ""
    ).strip()
    if configured:
        parts = shlex.split(configured)
        if parts and executable(parts[0]):
            parts[0] = executable(parts[0]) or parts[0]
            return parts

    for name in ("kitty", "foot", "alacritty", "wezterm", "konsole", "gnome-terminal"):
        found = executable(name)
        if found:
            return [found]
    raise ValueError(
        "no supported terminal found; set OPERATIONS_CENTER_TERMINAL or TERMINAL"
    )


def open_terminal(pid: int, start_ticks: int = 0) -> dict:
    ensure_safe_process(pid, start_ticks)
    cwd = proc_cwd(pid)
    if not cwd:
        raise ValueError("process working directory is unavailable")
    command = terminal_command()
    subprocess.Popen(
        command,
        cwd=cwd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    return {"ok": True, "message": f"Opened terminal in {display_path(cwd)}"}



def runtime_for_action(pid: int, start_ticks: int = 0) -> dict:
    identity = ensure_safe_process(pid, start_ticks)
    for runtime in parse_ss(process_table()):
        if int(runtime.get("pid", 0)) != pid:
            continue
        if start_ticks and int(runtime.get("start_ticks", 0)) != start_ticks:
            continue
        return runtime
    raise ValueError("runtime is no longer listening")


def clipboard_copy(value: str) -> None:
    wl_copy = executable("wl-copy")
    if wl_copy:
        subprocess.run(
            [wl_copy], input=value, text=True,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            timeout=3.0, check=True,
        )
        return
    xclip = executable("xclip")
    if xclip:
        subprocess.run(
            [xclip, "-selection", "clipboard"], input=value, text=True,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            timeout=3.0, check=True,
        )
        return
    raise ValueError("clipboard helper unavailable (install wl-clipboard or xclip)")


def copy_runtime_value(pid: int, start_ticks: int, mode: str) -> dict:
    runtime = runtime_for_action(pid, start_ticks)
    if mode == "url":
        value = str(runtime.get("url", ""))
        if not value:
            raise ValueError("runtime does not expose an HTTP(S) URL")
    elif mode == "port":
        value = str(runtime.get("port", ""))
    elif mode == "endpoint":
        value = str(runtime.get("endpoint", ""))
    else:
        raise ValueError("invalid copy mode")
    if not value:
        raise ValueError("runtime value is unavailable")
    clipboard_copy(value)
    label = "URL" if mode == "url" else ("port" if mode == "port" else "endpoint")
    return {"ok": True, "message": f"Copied {label}: {value}"}


def open_runtime_folder(pid: int, start_ticks: int = 0) -> dict:
    ensure_safe_process(pid, start_ticks)
    cwd = proc_cwd(pid)
    if not cwd:
        raise ValueError("process working directory is unavailable")
    command = configured_command("file_manager")
    if command:
        subprocess.Popen(
            command + [cwd], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    else:
        xdg_open = executable("xdg-open")
        if not xdg_open:
            raise ValueError("no file manager configured and xdg-open is unavailable")
        subprocess.Popen(
            [xdg_open, cwd], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    return {"ok": True, "message": f"Opened {display_path(cwd)}"}


def editor_command() -> list[str]:
    command = configured_command("editor")
    if command:
        return command
    for name in ("zed", "code", "codium", "kate", "subl"):
        found = executable(name)
        if found:
            return [found]
    raise ValueError("no supported editor found; configure actions.editor")


def open_runtime_editor(pid: int, start_ticks: int = 0) -> dict:
    ensure_safe_process(pid, start_ticks)
    cwd = proc_cwd(pid)
    if not cwd:
        raise ValueError("process working directory is unavailable")
    command = editor_command()
    subprocess.Popen(
        command + [cwd], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    return {"ok": True, "message": f"Opened editor in {display_path(cwd)}"}


def _proc_cgroup_path(pid: int) -> str:
    try:
        rows = Path(f"/proc/{pid}/cgroup").read_text(
            encoding="utf-8",
            errors="replace",
        ).splitlines()
    except OSError:
        return ""

    fallback = ""
    for row in rows:
        parts = row.split(":", 2)
        if len(parts) != 3:
            continue
        hierarchy, _controllers, path = parts
        if path:
            fallback = path
        if hierarchy == "0":
            return path
    return fallback


def _user_service_unit_from_cgroup_path(cgroup_path: str) -> str:
    # Only return a service unit. A normal terminal-launched runtime can live
    # inside the terminal's .scope; stopping that scope would kill unrelated UI.
    for component in reversed(str(cgroup_path).split("/")):
        if not component.endswith(".service"):
            continue
        if component.startswith("user@"):
            continue
        return component
    return ""


def _parse_systemd_show(text: str) -> dict[str, str]:
    values = {}
    for line in str(text).splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key] = value
    return values


def _runtime_user_service(pid: int) -> str:
    cgroup_path = _proc_cgroup_path(pid)
    unit = _user_service_unit_from_cgroup_path(cgroup_path)
    if not unit:
        return ""

    lowered = unit.lower()
    if unit == "nyvorel-operations-monitor.service":
        return ""
    if "quickshell" in lowered:
        return ""

    systemctl = executable("systemctl")
    if not systemctl:
        return ""

    try:
        result = subprocess.run(
            [
                systemctl,
                "--user",
                "show",
                unit,
                "--property=MainPID",
                "--property=ControlGroup",
                "--property=ActiveState",
                "--no-pager",
            ],
            capture_output=True,
            text=True,
            timeout=3.0,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return ""

    if result.returncode != 0:
        return ""

    props = _parse_systemd_show(result.stdout)
    try:
        main_pid = int(props.get("MainPID", "0") or 0)
    except ValueError:
        return ""

    # MainPID is the ownership proof. It prevents a child runtime from causing
    # its terminal/app service to be stopped.
    if main_pid != pid:
        return ""

    control_group = props.get("ControlGroup", "").rstrip("/")
    target_group = cgroup_path.rstrip("/")
    if control_group and not (
        target_group == control_group
        or target_group.startswith(control_group + "/")
    ):
        return ""

    if props.get("ActiveState", "") not in ("active", "activating", "reloading"):
        return ""

    return unit


def _same_process_identity(pid: int, start_ticks: int) -> bool:
    if proc_uid(pid) != os.getuid():
        return False
    actual = proc_start_ticks(pid)
    return actual > 0 and actual == start_ticks


def _wait_process_identity_gone(
    pid: int,
    start_ticks: int,
    timeout_seconds: float,
) -> bool:
    import time

    deadline = time.monotonic() + max(0.0, timeout_seconds)
    while time.monotonic() < deadline:
        if not _same_process_identity(pid, start_ticks):
            return True
        time.sleep(0.05)
    return not _same_process_identity(pid, start_ticks)


def _runtime_with_pin_key(pin_key: str) -> dict | None:
    if not pin_key:
        return None
    try:
        runtimes = parse_ss(process_table())
    except Exception:
        return None
    for runtime in runtimes:
        if str(runtime.get("pin_key", "")) == pin_key:
            return runtime
    return None


def _wait_runtime_pin_gone(pin_key: str, timeout_seconds: float) -> dict | None:
    import time

    deadline = time.monotonic() + max(0.0, timeout_seconds)
    current = _runtime_with_pin_key(pin_key)
    while current is not None and time.monotonic() < deadline:
        time.sleep(0.10)
        current = _runtime_with_pin_key(pin_key)
    return current


def stop_process(
    pid: int,
    start_ticks: int = 0,
    expected_pin_key: str = "",
) -> dict:
    runtime = runtime_for_action(pid, start_ticks)
    if runtime.get("managed_by_arch_remote"):
        raise ValueError(
            f"{runtime.get('name', 'Remote service')} is managed by Arch Remote"
        )

    actual_start_ticks = int(runtime.get("start_ticks", 0) or 0)
    actual_pin_key = str(runtime.get("pin_key", ""))

    if expected_pin_key:
        if not re.fullmatch(r"[0-9a-f]{20}", expected_pin_key):
            raise ValueError("invalid runtime identity")
        if expected_pin_key != actual_pin_key:
            raise ValueError("runtime identity changed; refusing stale stop action")

    ensure_safe_process(pid, actual_start_ticks)

    unit = _runtime_user_service(pid)
    escalated = False

    if unit:
        systemctl = executable("systemctl")
        if not systemctl:
            raise ValueError("systemctl is unavailable")

        try:
            result = subprocess.run(
                [systemctl, "--user", "stop", unit],
                capture_output=True,
                text=True,
                timeout=6.0,
                check=False,
            )
        except subprocess.TimeoutExpired as error:
            raise ValueError(f"timed out stopping owning service {unit}") from error

        if result.returncode != 0:
            detail = (result.stderr or result.stdout or "").strip()
            raise ValueError(
                f"failed to stop owning service {unit}"
                + (f": {detail}" if detail else "")
            )

        if not _wait_process_identity_gone(pid, actual_start_ticks, 1.5):
            ensure_safe_process(pid, actual_start_ticks)
            os.kill(pid, signal.SIGTERM)

        if not _wait_process_identity_gone(pid, actual_start_ticks, 1.0):
            ensure_safe_process(pid, actual_start_ticks)
            os.kill(pid, signal.SIGKILL)
            escalated = True
            _wait_process_identity_gone(pid, actual_start_ticks, 0.75)
    else:
        os.kill(pid, signal.SIGTERM)

        if not _wait_process_identity_gone(pid, actual_start_ticks, 1.5):
            ensure_safe_process(pid, actual_start_ticks)
            os.kill(pid, signal.SIGKILL)
            escalated = True
            _wait_process_identity_gone(pid, actual_start_ticks, 0.75)

    if _same_process_identity(pid, actual_start_ticks):
        raise ValueError("runtime process survived stop escalation")

    replacement = _wait_runtime_pin_gone(actual_pin_key, 1.5)
    if replacement is not None:
        replacement_pid = int(replacement.get("pid", 0) or 0)
        raise ValueError(
            "runtime restarted under a new PID"
            + (f" {replacement_pid}" if replacement_pid > 0 else "")
            + "; stop its owning supervisor/service"
        )

    if unit:
        # Some Node-based services exit with code 143 after systemd's expected
        # SIGTERM. Clear only that stop-induced failed state after proving the
        # process stayed gone; preserve every other failed service for review.
        status = run(
            [systemctl, "--user", "show", unit,
             "--property=ActiveState", "--property=Result",
             "--property=ExecMainStatus", "--no-pager"],
            timeout=3.0,
        )
        props = _parse_systemd_show(status.stdout) if status.returncode == 0 else {}
        if (props.get("ActiveState") == "failed"
                and props.get("Result") == "exit-code"
                and props.get("ExecMainStatus") == "143"):
            run([systemctl, "--user", "reset-failed", unit], timeout=3.0)
        suffix = " (forced final PID teardown)" if escalated else ""
        return {
            "ok": True,
            "message": f"Stopped runtime service {unit}{suffix}",
        }

    return {
        "ok": True,
        "message": (
            f"Stopped runtime PID {pid}"
            + (" (SIGKILL escalation)" if escalated else "")
        ),
    }


def stop_operation(pid: int, start_ticks: int) -> dict:
    ensure_safe_process(pid, start_ticks)
    table = process_table()
    if pid not in table:
        raise ValueError("operation no longer exists")
    descendants = []
    for candidate in table:
        if candidate == pid:
            continue
        if pid in ancestor_chain(candidate, table):
            descendants.append(candidate)
    # Children first. Identity/ownership are checked immediately before signal.
    signalled = 0
    for candidate in sorted(descendants, key=lambda p: len(ancestor_chain(p, table)), reverse=True):
        try:
            ensure_safe_process(candidate, int(table[candidate].get("start_ticks", 0)))
            os.kill(candidate, signal.SIGTERM)
            signalled += 1
        except (ProcessLookupError, ValueError):
            continue
    ensure_safe_process(pid, start_ticks)
    os.kill(pid, signal.SIGTERM)
    signalled += 1
    return {"ok": True, "message": f"Stopped operation ({signalled} process{'es' if signalled != 1 else ''})"}


def toggle_pin(key: str) -> dict:
    if not re.match(r"^[0-9a-f]{20}$", key):
        raise ValueError("invalid runtime pin key")
    with locked_state() as app_state:
        pins = list(str(item) for item in app_state.get("pinned_runtime_keys", []))
        if key in pins:
            pins.remove(key)
            pinned = False
        else:
            pins.append(key)
            pinned = True
        app_state["pinned_runtime_keys"] = pins[-30:]
        save_state(app_state)
    return {"ok": True, "pinned": pinned, "message": "Pinned runtime" if pinned else "Unpinned runtime"}



def migrate_state() -> dict:
    with locked_state() as app_state:
        save_state(app_state)
        return {
            "ok": True,
            "schema_version": app_state.get("schema_version", SCHEMA_VERSION),
            "history_count": len(app_state.get("operation_history", [])),
            "privacy_migrated": True,
        }

def open_arch_remote() -> dict:
    qs = executable("qs") or executable("quickshell")
    if not qs:
        raise ValueError("Quickshell IPC executable is unavailable")
    result = run([qs, "-c", QS_CONFIG, "ipc", "call", "archRemote", "open"], timeout=4.0)
    if result.returncode != 0:
        message = (result.stderr or result.stdout).strip()
        raise ValueError(message or "Arch Remote IPC target is unavailable")
    return {"ok": True, "message": "Opened Arch Remote"}


def contract() -> dict:
    return {
        "schema_version": SCHEMA_VERSION,
        "ui_contract": UI_CONTRACT,
        "backend_revision": BACKEND_REVISION,
        "monitor_interval_seconds": MONITOR_INTERVAL,
        "monitor_fresh_seconds": MONITOR_FRESH_SECONDS,
        "history_privacy": "minimal",
        "process_scope": "current-user",
        "runtime_command_exposed": False,
        "operation_command_exposed": False,
        "arch_remote_ownership": "positive-evidence",
        "config_path": display_path(str(CONFIG_PATH)),
        "runtime_filters": True,
        "custom_detectors": True,
        "configurable_actions": True,
    }


def output(payload) -> int:
    print(json.dumps(payload, ensure_ascii=False))
    return 0


def _arg_int(index: int, default: int = 0) -> int:
    try:
        return int(sys.argv[index])
    except (IndexError, ValueError):
        return default



def self_test() -> dict:
    original_proc_cwd = globals()["proc_cwd"]
    cwd_map: dict[int, str] = {}

    def fake_cwd(pid: int) -> str:
        return cwd_map.get(pid, "/tmp/project")

    globals()["proc_cwd"] = fake_cwd
    try:
        def row(pid, ppid, pgid, sid, args, comm="node", elapsed=10, start=None):
            return {
                "pid": pid,
                "ppid": ppid,
                "pgid": pgid,
                "sid": sid,
                "elapsed": elapsed,
                "cpu": 1.0,
                "rss_kib": 1024,
                "comm": comm,
                "args": args,
                "start_ticks": start if start is not None else pid * 10,
            }

        checks = []

        # One shell workflow with sequential build phases must be one operation.
        table = {
            100: row(100, 50, 100, 50, "bash -c pnpm build:web && pnpm build:worker", "bash", 30),
            101: row(101, 100, 101, 50, "node /x/pnpm build:web", "node", 5),
            102: row(102, 101, 101, 50, "next build", "node", 4),
        }
        cwd_map.update({100: "/tmp/project", 101: "/tmp/project", 102: "/tmp/project"})
        ops = discover_operations(table, set())
        checks.append(("sequential_build_collapsed", len(ops) == 1 and ops[0]["kind"] == "Build" and ops[0]["root_pid"] == 100 and ops[0]["process_count"] == 3))

        # Mixed test/build shell workflow must remain one truthful Workflow.
        table = {
            200: row(200, 50, 200, 50, "bash -c pnpm test && pnpm build", "bash", 20),
            201: row(201, 200, 201, 50, "node /x/pnpm build", "node", 5),
        }
        cwd_map.update({200: "/tmp/project", 201: "/tmp/project"})
        ops = discover_operations(table, set())
        checks.append(("mixed_workflow_collapsed", len(ops) == 1 and ops[0]["kind"] == "Workflow" and set(ops[0]["component_kinds"]) == {"Build", "Tests"}))

        # Agent and a build it launches are distinct operations, not one blob.
        table = {
            300: row(300, 50, 300, 50, "opencode", "opencode", 100),
            301: row(301, 300, 301, 50, "node /x/pnpm build", "node", 8),
        }
        cwd_map.update({300: "/tmp/project", 301: "/tmp/project"})
        ops = discover_operations(table, set())
        checks.append(("agent_build_separate", len(ops) == 2 and {op["kind"] for op in ops} == {"Agent", "Build"}))

        # Two unrelated builds are not merged merely because they share session.
        table = {
            400: row(400, 50, 400, 50, "node /x/pnpm build:a", "node", 8),
            401: row(401, 50, 401, 50, "node /x/pnpm build:b", "node", 7),
        }
        cwd_map.update({400: "/tmp/project", 401: "/tmp/project"})
        ops = discover_operations(table, set())
        checks.append(("independent_builds_separate", len(ops) == 2))

        # Next internal jest-worker must never become a test operation.
        table = {
            500: row(500, 50, 500, 50, "/node next/dist/compiled/jest-worker/processChild.js", "node", 3),
        }
        cwd_map[500] = "/tmp/project"
        ops = discover_operations(table, set())
        checks.append(("next_jest_worker_ignored", len(ops) == 0))

        # PID identity continuity fallback: root handoff in same PGID keeps ID.
        previous = [{
            "key": "600:6000", "operation_id": "600:6000", "root_pid": 600,
            "root_start_ticks": 6000, "pgid": 600, "sid": 50, "project_key": project_identity("/tmp/project"),
            "kind": "Build", "started_at": 1000.0, "last_seen_at": 1010.0,
        }]
        current = [{
            "key": "601:6010", "operation_id": "601:6010", "root_pid": 601,
            "root_start_ticks": 6010, "pgid": 600, "sid": 50, "project_key": project_identity("/tmp/project"),
            "kind": "Build", "started_at": 1008.0, "last_seen_at": 1011.0, "elapsed": 3,
        }]
        merged = reconcile_operation_continuity(current, previous, 1011.0)
        checks.append(("pgid_handoff_preserves_identity", len(merged) == 1 and merged[0]["key"] == "600:6000" and merged[0]["started_at"] == 1000.0))

        previous = [{
            "key": "700:7000", "operation_id": "700:7000", "root_pid": 700,
            "root_start_ticks": 7000, "pgid": 700, "sid": 50, "project_key": project_identity("/tmp/project"),
            "kind": "Workflow", "name": "Build + Tests", "component_kinds": ["Build", "Tests"],
            "workflow_wrapper": True, "started_at": 1000.0, "last_seen_at": 1010.0,
        }]
        current = [{
            "key": "700:7000", "operation_id": "700:7000", "root_pid": 700,
            "root_start_ticks": 7000, "pgid": 700, "sid": 50, "project_key": project_identity("/tmp/project"),
            "kind": "Build", "name": "Build", "component_kinds": ["Build"],
            "workflow_wrapper": False,
            "started_at": 1008.0, "last_seen_at": 1011.0, "elapsed": 3,
        }]
        merged = reconcile_operation_continuity(current, previous, 1011.0)
        checks.append((
            "workflow_identity_survives_exec",
            len(merged) == 1
            and merged[0]["kind"] == "Workflow"
            and merged[0]["name"] == "Build + Tests"
            and "command" not in merged[0]
            and "origin_command" not in merged[0]
        ))

        checks.extend([
            (
                "generic_python_8000_not_arch_remote",
                not arch_remote_owner("python3", 8000, "python manage.py runserver")["managed"],
            ),
            (
                "lan_share_requires_positive_identity",
                arch_remote_owner(
                    "python3",
                    8000,
                    "/usr/bin/python3 /home/user/.local/share/lan-share/app.py run",
                )["managed"],
            ),
            (
                "generic_wayvnc_not_arch_remote",
                not arch_remote_owner("wayvnc", 5900, "/usr/bin/wayvnc 127.0.0.1:5900")["managed"],
            ),
            (
                "arch_remote_wayvnc_positive_identity",
                arch_remote_owner(
                    "wayvnc",
                    5900,
                    "/usr/bin/wayvnc --config /home/user/.config/wayvnc/arch-remote.conf 100.64.0.2:5900",
                )["managed"],
            ),
            (
                "history_privacy_sanitizer",
                sanitize_history_record({
                    "name": "Build",
                    "kind": "Build",
                    "command": "curl --token secret",
                    "origin_command": "TOKEN=secret pnpm build",
                    "cwd": "/home/user/private",
                    "project_root": "/home/user/private",
                    "member_pids": [1, 2],
                }) == {"name": "Build", "kind": "Build"},
            ),
            (
                "home_path_redaction",
                display_path(str(HOME / "dev" / "project")) == "~/dev/project",
            ),
        ])

        checks.extend([
            (
                "ss_inline_owner_parser_accepts_truncated_next_name",
                _ss_inline_owners(
                    'LISTEN 0 511 127.0.0.1:3210 0.0.0.0:* '
                    'users:(("next-server (v1",pid=1036637,fd=21)) '
                    'uid:1000 ino:12345 sk:abc'
                ) == [("next-server (v1", 1036637)],
            ),
            (
                "next_server_comm_classifies_as_nextjs",
                runtime_kind(
                    "next-server (v1",
                    "/tmp/no-package",
                    "next-server (v16.3.6)",
                    3210,
                ) == "Next.js",
            ),
            (
                "proc_tcp_ipv4_loopback_decode",
                _decode_proc_net_address("0100007F", False) == "127.0.0.1",
            ),
            (
                "proc_tcp_port_decode_reference",
                int("0C8A", 16) == 3210,
            ),
        ])

        detector = {
            "ports": [8787],
            "process_contains": "worker-api",
            "cwd_contains": "",
        }
        checks.extend([
            (
                "phase2_custom_detector_matches_port_and_process",
                detector_matches(detector, "python3", "worker-api serve", "/tmp/app", 8787),
            ),
            (
                "phase2_custom_detector_rejects_wrong_port",
                not detector_matches(detector, "python3", "worker-api serve", "/tmp/app", 8788),
            ),
            (
                "phase2_runtime_ignore_port",
                runtime_ignored({"runtime": {"ignore_ports": [4321], "ignore_processes": []}}, "node", "next-server", 4321),
            ),
            (
                "phase2_runtime_ignore_process",
                runtime_ignored({"runtime": {"ignore_ports": [], "ignore_processes": ["language-server"]}}, "node", "yaml-language-server --stdio", 9999),
            ),
        ])

        failures = [name for name, ok in checks if not ok]
        if failures:
            raise AssertionError("; ".join(failures))
        return {"ok": True, "scenario_count": len(checks), "checks": [name for name, _ in checks]}
    finally:
        globals()["proc_cwd"] = original_proc_cwd

def main() -> int:
    if len(sys.argv) < 2:
        return output({"error": True, "message": "missing command"})
    command = sys.argv[1]
    try:
        if command == "contract":
            return output(contract())
        if command == "snapshot":
            return output(snapshot())
        if command == "monitor":
            return monitor_forever()
        if command == "monitor-once":
            return output(monitor_once())
        if command == "system":
            return output(system_snapshot(force="--force" in sys.argv[2:]))
        if command == "migrate-state":
            return output(migrate_state())
        if command == "self-test":
            return output(self_test())
        if command == "open":
            return output(open_url(sys.argv[2]))
        if command == "terminal":
            return output(open_terminal(_arg_int(2), _arg_int(3)))
        if command == "copy-runtime":
            return output(copy_runtime_value(_arg_int(2), _arg_int(3), sys.argv[4]))
        if command == "open-folder":
            return output(open_runtime_folder(_arg_int(2), _arg_int(3)))
        if command == "open-editor":
            return output(open_runtime_editor(_arg_int(2), _arg_int(3)))
        if command == "stop":
            return output(
                stop_process(
                    _arg_int(2),
                    _arg_int(3),
                    sys.argv[4] if len(sys.argv) > 4 else "",
                )
            )
        if command == "stop-operation":
            return output(stop_operation(_arg_int(2), _arg_int(3)))
        if command == "toggle-pin":
            return output(toggle_pin(sys.argv[2]))
        if command == "open-remote":
            return output(open_arch_remote())
        raise ValueError(f"unknown command: {command}")
    except Exception as error:
        return output({"error": True, "message": str(error)})


if __name__ == "__main__":
    raise SystemExit(main())
