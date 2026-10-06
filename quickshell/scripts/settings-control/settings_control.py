#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from copy import deepcopy
from pathlib import Path

XDG_CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
CONFIG_PATH = XDG_CONFIG / "nyvorel" / "config.json"
STATE_DIR = Path.home() / ".local" / "state" / "nyvorel" / "settings-control"
STATE_PATH = STATE_DIR / "state.json"
BACKUP_DIR = STATE_DIR / "backups"
MISSING = {"__missing__": True}


def load_json(path: Path, default):
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except Exception:
        return deepcopy(default)


def atomic_write_json(path: Path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
    temp = Path(temp_name)
    try:
        with os.fdopen(fd, "w") as handle:
            json.dump(value, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)


def load_state():
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    state = load_json(STATE_PATH, {"baseline": None, "history": [], "favorites": [], "last_backup": ""})
    state.setdefault("baseline", None)
    state.setdefault("history", [])
    state.setdefault("favorites", [])
    state.setdefault("last_backup", "")
    return state


def save_state(state):
    atomic_write_json(STATE_PATH, state)


def flatten(value, prefix=""):
    output = {}
    if isinstance(value, dict):
        for key, child in value.items():
            path = f"{prefix}.{key}" if prefix else key
            if isinstance(child, dict):
                output.update(flatten(child, path))
            else:
                output[path] = child
    else:
        output[prefix] = value
    return output


def diff_configs(old, new):
    old_flat = flatten(old)
    new_flat = flatten(new)
    changes = []
    for path in sorted(set(old_flat) | set(new_flat)):
        before = old_flat.get(path, MISSING)
        after = new_flat.get(path, MISSING)
        if before != after:
            changes.append({"path": path, "old": deepcopy(before), "new": deepcopy(after)})
    return changes


def set_path(root, dotted, value):
    parts = dotted.split(".")
    node = root
    for part in parts[:-1]:
        child = node.get(part)
        if not isinstance(child, dict):
            child = {}
            node[part] = child
        node = child
    leaf = parts[-1]
    if isinstance(value, dict) and value.get("__missing__") is True:
        node.pop(leaf, None)
    else:
        node[leaf] = deepcopy(value)


def read_config():
    try:
        with CONFIG_PATH.open("r", encoding="utf-8") as handle:
            value = json.load(handle)
    except Exception as error:
        raise ValueError(f"{CONFIG_PATH}: {error}") from error
    if not isinstance(value, dict):
        raise ValueError(f"{CONFIG_PATH}: root must be a JSON object")
    return value


def find_executable(name):
    found = shutil.which(name)
    if found:
        return found
    for candidate in (Path("/usr/bin") / name, Path("/usr/local/bin") / name, Path.home() / ".local/bin" / name):
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def run_command(command, timeout=4.0, env=None):
    try:
        return subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=timeout, env=env, check=False)
    except Exception as error:
        return subprocess.CompletedProcess(command, 127, "", str(error))


def candidate_hyprland_envs():
    envs = [os.environ.copy()]
    active = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "hypr"
    if runtime.is_dir():
        try:
            instances = sorted([item for item in runtime.iterdir() if item.is_dir()], key=lambda item: item.stat().st_mtime, reverse=True)
        except Exception:
            instances = []
        for item in instances[:8]:
            if item.name == active:
                continue
            env = os.environ.copy()
            env["HYPRLAND_INSTANCE_SIGNATURE"] = item.name
            envs.append(env)
    return envs


def run_hyprctl(*args):
    binary = find_executable("hyprctl")
    if not binary:
        return subprocess.CompletedProcess(["hyprctl", *args], 127, "", "hyprctl not found")
    last = None
    for env in candidate_hyprland_envs():
        result = run_command([binary, *args], env=env)
        last = result
        if result.returncode == 0:
            return result
    return last or subprocess.CompletedProcess([binary, *args], 127, "", "Hyprland unavailable")


def process_rows():
    ps = find_executable("ps")
    if not ps:
        return []
    result = run_command([ps, "-eo", "pid=,args="], timeout=3.0)
    if result.returncode != 0:
        return []
    rows = []
    for line in result.stdout.splitlines():
        match = re.match(r"^\s*(\d+)\s+(.*)$", line)
        if match:
            rows.append((int(match.group(1)), match.group(2)))
    return rows


def shell_process_info():
    main_pids = []
    settings_pids = []
    for pid, command in process_rows():
        normalized = " ".join(command.split())
        if re.search(r"(^|[/\s])(qs|quickshell)\s+-c\s+ii(?:\s|$)", normalized):
            main_pids.append(pid)
        if re.search(r"(^|[/\s])(qs|quickshell)\s+-p\s+\S*settings\.qml(?:\s|$)", normalized):
            settings_pids.append(pid)
    return {
        "shell_running": bool(main_pids),
        "shell_pids": main_pids,
        "settings_running": bool(settings_pids),
        "settings_pids": settings_pids,
    }


def parse_hyprland_version(text):
    match = re.search(r"\bHyprland\s+([0-9]+\.[0-9]+(?:\.[0-9]+)?)", text)
    return match.group(1) if match else ""


def current_hyprland_config():
    explicit = os.environ.get("HYPRLAND_CONFIG", "").strip()
    if explicit:
        return Path(os.path.expandvars(os.path.expanduser(explicit)))
    return XDG_CONFIG / "hypr/hyprland.conf"


def hyprland_health():
    version_result = run_hyprctl("version")
    hyprland_ok = version_result.returncode == 0
    version_raw = version_result.stdout if version_result.stdout.strip() else version_result.stderr
    version = parse_hyprland_version(version_raw)

    errors_result = run_hyprctl("configerrors")
    config_errors_available = errors_result.returncode == 0
    config_errors = []
    if config_errors_available:
        config_errors = [line.strip() for line in errors_result.stdout.splitlines() if line.strip()]

    config_path = current_hyprland_config()
    legacy_conf = config_path.exists() and config_path.suffix.lower() == ".conf"
    warnings = []
    if legacy_conf:
        warnings.append({
            "code": "hyprland-conf-deprecated",
            "title": "Legacy Hyprland .conf configuration",
            "detail": "The current .conf format is deprecated and is scheduled for removal in Hyprland 0.57.",
            "path": str(config_path),
        })

    return {
        "hyprland_ok": hyprland_ok,
        "hyprland_version": version,
        "hyprland_config_errors_available": config_errors_available,
        "hyprland_config_errors": config_errors,
        "hyprland_config_error_count": len(config_errors),
        "hyprland_config_path": str(config_path),
        "hyprland_legacy_conf": legacy_conf,
        "warnings": warnings,
    }


def health_summary(state):
    payload = {
        "config_path": str(CONFIG_PATH),
        "state_path": str(STATE_PATH),
        "last_backup": state.get("last_backup", ""),
        "favorite_count": len(state.get("favorites", [])),
        "history_count": sum(len(item.get("changes", [])) for item in state.get("history", [])),
        "can_undo": len(state.get("history", [])) > 0,
    }

    try:
        read_config()
        config_valid = True
        config_error = ""
    except Exception as error:
        config_valid = False
        config_error = str(error)

    payload["config_valid"] = config_valid
    payload["config_error"] = config_error

    process_health = shell_process_info()
    payload.update(process_health)

    hypr_health = hyprland_health()
    payload.update(hypr_health)

    critical = []
    if not config_valid:
        critical.append({"code": "config-invalid", "title": "config.json is invalid", "detail": config_error})
    if not hypr_health["hyprland_ok"]:
        critical.append({"code": "hyprland-unavailable", "title": "Hyprland integration unavailable", "detail": "hyprctl could not contact the active Hyprland session."})
    if not process_health["shell_running"]:
        critical.append({"code": "quickshell-main-missing", "title": "Main Quickshell instance not detected", "detail": "Expected qs/quickshell -c nyvorel."})
    if hypr_health["hyprland_config_errors_available"] and hypr_health["hyprland_config_error_count"] > 0:
        critical.append({"code": "hyprland-config-errors", "title": "Hyprland reports configuration errors", "detail": "\n".join(hypr_health["hyprland_config_errors"][:8])})

    payload["critical_issues"] = critical
    payload["critical_count"] = len(critical)
    payload["warning_count"] = len(hypr_health["warnings"])
    payload["diagnostics_ok"] = len(critical) == 0
    return payload


def command_snapshot():
    state = load_state()
    try:
        current = read_config()
    except Exception:
        return health_summary(state)
    baseline = state.get("baseline")
    if not isinstance(baseline, dict):
        state["baseline"] = current
        save_state(state)
        return health_summary(state)
    changes = diff_configs(baseline, current)
    if changes:
        state["history"].append({"timestamp": time.time(), "changes": changes[:120]})
        state["history"] = state["history"][-50:]
        state["baseline"] = current
        save_state(state)
    return health_summary(state)


def command_status():
    return health_summary(load_state())


def command_favorites():
    state = load_state()
    payload = health_summary(state)
    payload["favorites"] = state["favorites"]
    return payload


def command_toggle_favorite(item_id):
    state = load_state()
    favorites = list(state.get("favorites", []))
    if item_id in favorites:
        favorites.remove(item_id)
        message = "Removed from favorites"
    else:
        favorites.append(item_id)
        message = "Added to favorites"
    state["favorites"] = favorites[-80:]
    save_state(state)
    payload = health_summary(state)
    payload["favorites"] = state["favorites"]
    payload["message"] = message
    return payload


def command_history():
    state = load_state()
    payload = health_summary(state)
    payload["history"] = state.get("history", [])
    return payload


def make_backup(prefix="manual"):
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    target = BACKUP_DIR / f"{prefix}-{stamp}.json"
    shutil.copy2(CONFIG_PATH, target)
    return target


def command_backup():
    state = load_state()
    target = make_backup("manual")
    state["last_backup"] = str(target)
    save_state(state)
    payload = health_summary(state)
    payload["message"] = f"Backup created: {target.name}"
    return payload


def command_undo():
    state = load_state()
    history = state.get("history", [])
    if not history:
        payload = health_summary(state)
        payload["message"] = "Nothing to undo"
        return payload
    current = read_config()
    make_backup("before-undo")
    event = history.pop()
    for change in event.get("changes", []):
        set_path(current, change["path"], change["old"])
    atomic_write_json(CONFIG_PATH, current)
    state["history"] = history
    state["baseline"] = current
    save_state(state)
    payload = health_summary(state)
    count = len(event.get("changes", []))
    payload["message"] = f"Undid {count} change" + ("" if count == 1 else "s")
    return payload


def command_restore_latest():
    state = load_state()
    candidates = sorted(BACKUP_DIR.glob("*.json"), key=lambda path: path.stat().st_mtime, reverse=True)
    if not candidates:
        payload = health_summary(state)
        payload["message"] = "No configuration backup exists yet"
        return payload
    latest = candidates[0]
    restored = load_json(latest, None)
    if not isinstance(restored, dict):
        payload = health_summary(state)
        payload["message"] = f"Backup is invalid: {latest.name}"
        return payload
    make_backup("before-restore")
    atomic_write_json(CONFIG_PATH, restored)
    state["baseline"] = restored
    state["history"] = []
    save_state(state)
    payload = health_summary(state)
    payload["message"] = f"Restored {latest.name}"
    return payload


def main():
    if len(sys.argv) < 2:
        print(json.dumps({"error": "missing command"}))
        return 2
    command = sys.argv[1]
    try:
        if command == "snapshot":
            payload = command_snapshot()
        elif command == "status":
            payload = command_status()
        elif command == "favorites":
            payload = command_favorites()
        elif command == "toggle-favorite":
            if len(sys.argv) < 3:
                raise ValueError("missing favorite id")
            payload = command_toggle_favorite(sys.argv[2])
        elif command == "history":
            payload = command_history()
        elif command == "undo":
            payload = command_undo()
        elif command == "backup":
            payload = command_backup()
        elif command == "restore-latest":
            payload = command_restore_latest()
        else:
            raise ValueError(f"unknown command: {command}")
    except Exception as error:
        state = load_state()
        payload = health_summary(state)
        payload["message"] = str(error)
        payload["error"] = True
    print(json.dumps(payload, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
