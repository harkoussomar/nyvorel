#!/usr/bin/env python3
from __future__ import annotations

import fcntl
import hashlib
import json
import os
import re
import shutil
import socket
import stat
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid
from contextlib import contextmanager
from pathlib import Path
from urllib.parse import urlparse

HOME = Path.home()
USER = os.environ.get("USER") or HOME.name
UID = os.getuid()

STATE_DIR = HOME / ".local/state/nyvorel/arch-remote"
CACHE_DIR = HOME / ".cache/nyvorel/arch-remote"
ACTIVITY_FILE = STATE_DIR / "activity.json"
RUNTIME_FILE = STATE_DIR / "runtime-state.json"
SLOW_CACHE = CACHE_DIR / "slow-state.json"
EXPORT_DIR = STATE_DIR / "exports"
QR_DIR = CACHE_DIR / "qr"

SSH_DROPIN = Path("/etc/ssh/sshd_config.d/99-remote.conf")
LID_DROPIN = Path("/etc/systemd/logind.conf.d/90-remote-access.conf")
WOWLAN_FILE = Path("/etc/NetworkManager/dispatcher.d/90-wowlan")
AUTHORIZED_KEYS = HOME / ".ssh/authorized_keys"
SSH_HOST_ED25519_PUB = Path("/etc/ssh/ssh_host_ed25519_key.pub")
WAYVNC_CONFIG = HOME / ".config/wayvnc/arch-remote.conf"
WAYVNC_TLS_KEY = HOME / ".config/wayvnc/arch-remote-tls-key.pem"
WAYVNC_TLS_CERT = HOME / ".config/wayvnc/arch-remote-tls-cert.pem"
WAYVNC_LAUNCHER = HOME / ".local/bin/wayvnc-remote"
WAYVNC_SECURITY_DROPIN = HOME / ".config/systemd/user/wayvnc-remote.service.d/99-arch-remote-security.conf"
WAYVNC_SECURITY_REVISION = "2.2-phase1b2"
LAN_SHARE_HARDENING_DROPIN = HOME / ".config/systemd/user/lan-share.service.d/20-arch-remote-hardening.conf"
WAYVNC_HARDENING_DROPIN = HOME / ".config/systemd/user/wayvnc-remote.service.d/20-arch-remote-hardening.conf"
DEPLOYMENT_MANIFEST = STATE_DIR / "deployment.json"
HARDENING_REVISION = "3.0-phase3-final"

HARDENING_REQUIRED = {
    "NoNewPrivileges": "yes",
    "PrivateTmp": "yes",
    "ProtectSystem": "full",
    "ProtectKernelTunables": "yes",
    "ProtectKernelModules": "yes",
    "ProtectKernelLogs": "yes",
    "ProtectControlGroups": "yes",
    "ProtectClock": "yes",
    "ProtectHostname": "yes",
    "RestrictSUIDSGID": "yes",
    "LockPersonality": "yes",
    "RestrictRealtime": "yes",
    "RestrictNamespaces": "yes",
    "SystemCallArchitectures": "native",
    "UMask": "0077",
    "RestrictAddressFamilies": "AF_UNIX AF_INET AF_INET6",
}

USER_SERVICES = {"lan-share", "wayvnc-remote"}
LOG_UNITS = {
    "sshd": ("system", "sshd"),
    "tailscaled": ("system", "tailscaled"),
    "lan-share": ("user", "lan-share"),
    "wayvnc": ("user", "wayvnc-remote"),
}

SLOW_TTL = 90.0
ACTIVITY_LIMIT = 120
SSH_EFFECTIVE_CACHE = CACHE_DIR / "ssh-effective.json"
GENERATION_FILE = STATE_DIR / "generation.json"
PRIVILEGED_VERIFY_TTL = 86400.0
STATE_SCHEMA_VERSION = 2
UI_CONTRACT = "2.4.1"
BACKEND_REVISION = "2.4.1-phase3-final"
REFERENCE_SCHEMA_VERSION = 1

XDG_RUNTIME_DIR = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{UID}")
OP_RUNTIME_DIR = XDG_RUNTIME_DIR / "arch-remote"
ACTION_LOCK_FILE = OP_RUNTIME_DIR / "action.lock"
OPERATION_META_LOCK = OP_RUNTIME_DIR / "operation-meta.lock"
OPERATION_FILE = OP_RUNTIME_DIR / "operation.json"
STATE_DATA_LOCK = STATE_DIR / ".state.lock"
OPERATION_RESULT_MAX = 800


def emit(payload) -> int:
    print(json.dumps(payload, ensure_ascii=False))
    return 0


def exe(name: str) -> str | None:
    return shutil.which(name)


def resolve_lan_share_binary() -> str | None:
    """
    Resolve LAN Share independently from the GUI process PATH.

    Priority:
      1. ~/.local/bin/lan-share   (=> @HOME@/.local/bin/lan-share here)
      2. /usr/local/bin/lan-share
      3. PATH lookup as fallback
    """
    candidates = [
        HOME / ".local/bin/lan-share",
        Path("/usr/local/bin/lan-share"),
    ]

    for candidate in candidates:
        try:
            if candidate.is_file() and os.access(candidate, os.X_OK):
                return str(candidate)
        except OSError:
            continue

    fallback = shutil.which("lan-share")
    if fallback:
        try:
            path = Path(fallback)
            if path.is_file() and os.access(path, os.X_OK):
                return str(path)
        except OSError:
            pass

    return None


def run(command: list[str], timeout: float = 5.0, input_text: str | None = None):
    try:
        return subprocess.run(
            command,
            text=True,
            input=input_text,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
        )
    except Exception as error:
        return subprocess.CompletedProcess(command, 127, "", str(error))


def atomic_json(path: Path, payload) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(
        prefix=path.name + ".",
        suffix=".tmp",
        dir=path.parent,
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def load_json(path: Path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def ensure_private_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    try:
        path.chmod(0o700)
    except OSError:
        pass


@contextmanager
def advisory_lock(path: Path, blocking=True):
    ensure_private_dir(path.parent)
    fd = os.open(path, os.O_CREAT | os.O_RDWR, 0o600)
    acquired = False
    try:
        flags = fcntl.LOCK_EX | (0 if blocking else fcntl.LOCK_NB)
        try:
            fcntl.flock(fd, flags)
            acquired = True
        except BlockingIOError:
            acquired = False
        yield acquired
    finally:
        if acquired:
            try:
                fcntl.flock(fd, fcntl.LOCK_UN)
            except OSError:
                pass
        os.close(fd)


def next_generation() -> int:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    with advisory_lock(STATE_DATA_LOCK) as acquired:
        if not acquired:
            raise RuntimeError("Could not lock Arch Remote state generation")
        payload = load_json(GENERATION_FILE, {"generation": 0})
        try:
            generation = int(payload.get("generation", 0)) + 1
        except Exception:
            generation = 1
        atomic_json(GENERATION_FILE, {"generation": generation, "updated_at": time.time()})
        return generation


def record_activity(kind: str, title: str, detail: str, severity="info") -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    with advisory_lock(STATE_DATA_LOCK) as acquired:
        if not acquired:
            return
        payload = load_json(ACTIVITY_FILE, {"previous": {}, "events": []})
        events = list(payload.get("events", []))
        now = time.time()
        events.insert(0, {
            "id": f"{int(now * 1000)}-{kind}-{len(events)}",
            "timestamp": now,
            "kind": str(kind),
            "title": str(title),
            "detail": str(detail),
            "severity": str(severity),
        })
        payload["events"] = events[:ACTIVITY_LIMIT]
        atomic_json(ACTIVITY_FILE, payload)


def file_signature(paths: list[Path]) -> dict:
    result = {}
    for path in paths:
        try:
            st = path.stat()
            result[str(path)] = {"mtime_ns": st.st_mtime_ns, "size": st.st_size}
        except Exception:
            result[str(path)] = None
    return result


def ssh_config_signature() -> dict:
    return file_signature([Path("/etc/ssh/sshd_config"), SSH_DROPIN])


def sshd_runtime_signature() -> dict:
    """Bind cached sshd -T proof to config, executable, and daemon generation."""
    binary = Path("/usr/bin/sshd")
    signature = {
        "config": ssh_config_signature(),
        "binary": file_signature([binary]),
        "service": {},
    }
    systemctl = exe("systemctl")
    if not systemctl:
        signature["service"] = {"available": False}
        return signature

    result = run([
        systemctl, "show", "sshd.service", "--no-pager",
        "--property=MainPID,ActiveEnterTimestampMonotonic,FragmentPath,LoadState,ActiveState",
    ], timeout=4.0)
    values = {}
    if result.returncode == 0:
        for line in result.stdout.splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                values[key] = value
    signature["service"] = values or {"available": False}
    return signature


def parse_sshd_effective(text: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in text.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) == 2:
            values[parts[0].lower()] = parts[1].strip()
    return values


def run_sshd_effective(privileged=False) -> dict:
    binary = "/usr/bin/sshd" if Path("/usr/bin/sshd").is_file() else exe("sshd")
    if not binary:
        return {"ok": False, "values": {}, "error": "sshd executable is unavailable", "source": "none"}

    prefix = []
    source_prefix = ""
    if privileged:
        pkexec = exe("pkexec")
        if not pkexec:
            return {"ok": False, "values": {}, "error": "pkexec is unavailable", "source": "/usr/bin/sshd -T"}
        prefix = [pkexec]
        source_prefix = "pkexec "

    # Resolve Match rules for the intended account. Never replace failed
    # contextual evidence with a context-free policy result.
    command = [binary, "-T", "-C", f"user={USER},host=localhost,addr=127.0.0.1"]
    source = f"{source_prefix}{binary} -T -C user={USER},host=localhost,addr=127.0.0.1"
    required = {"permitrootlogin", "pubkeyauthentication", "passwordauthentication", "kbdinteractiveauthentication"}
    result = run(prefix + command, timeout=20.0 if privileged else 7.0)
    values = parse_sshd_effective(result.stdout) if result.returncode == 0 else {}
    if result.returncode == 0 and required.issubset(values):
        return {"ok": True, "values": values, "error": "", "source": source}
    error = (result.stderr or result.stdout).strip()[:600] or f"exit {result.returncode}"
    if not privileged and "no hostkeys available" in error.lower():
        error = ("The unprivileged SSH check could not load host keys. "
                 "Root-owned keys may be present but unreadable to this app. "
                 "Use Verify SSH to authorize a read-only policy check.")
    return {"ok": False, "values": {}, "error": error, "source": source}


def save_ssh_effective_cache(values: dict, source: str) -> None:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    atomic_json(SSH_EFFECTIVE_CACHE, {
        "checked_at": time.time(),
        "signature": sshd_runtime_signature(),
        "values": values,
        "source": source,
    })


def cached_ssh_effective() -> dict:
    payload = load_json(SSH_EFFECTIVE_CACHE, {})
    if not payload or payload.get("signature") != sshd_runtime_signature():
        return {"ok": False, "values": {}, "source": "", "checked_at": 0}
    values = payload.get("values") or {}
    age = time.time() - float(payload.get("checked_at", 0) or 0)
    if not values or age > PRIVILEGED_VERIFY_TTL:
        return {"ok": False, "values": {}, "source": "", "checked_at": 0}
    return {
        "ok": True,
        "values": values,
        "source": str(payload.get("source") or "cached sshd -T"),
        "checked_at": float(payload.get("checked_at", 0) or 0),
    }


def verify_ssh_effective() -> dict:
    attempt = run_sshd_effective(False)
    if not attempt["ok"]:
        attempt = run_sshd_effective(True)
    if not attempt["ok"]:
        record_activity("verification", "Effective SSH verification failed", attempt["error"], "warning")
        return {"error": True, "ok": False, "message": f"Could not verify effective SSH configuration: {attempt['error']}"}
    save_ssh_effective_cache(attempt["values"], attempt["source"])
    record_activity("verification", "Effective SSH configuration verified", attempt["source"], "success")
    return {"ok": True, "message": "Effective SSH configuration verified with sshd -T", "source": attempt["source"]}


def ssh_recent_auth_state() -> dict:
    journalctl = exe("journalctl")
    base = {
        "checked_at": time.time(),
        "last_success_at": 0.0,
        "last_success_ip": "",
        "last_success_message": "",
        "failure_count": 0,
        "source": "journalctl -u sshd",
    }
    if not journalctl:
        return base
    result = run([journalctl, "-u", "sshd", "--since", "24 hours ago", "-n", "240", "--no-pager", "-o", "json"], timeout=8.0)
    successes = []
    failures = 0
    for raw in result.stdout.splitlines():
        try:
            item = json.loads(raw)
        except Exception:
            continue
        message = str(item.get("MESSAGE") or "")
        lower = message.lower()
        try:
            timestamp = int(item.get("__REALTIME_TIMESTAMP") or 0) / 1_000_000.0
        except Exception:
            timestamp = 0.0
        if "accepted publickey" in lower:
            match = re.search(r" from ([0-9a-fA-F:.]+) port ", message)
            successes.append((timestamp, match.group(1) if match else "", message))
        if any(term in lower for term in ("authentication failure", "failed password", "invalid user", "failed publickey")):
            failures += 1
    if successes:
        successes.sort(key=lambda value: value[0], reverse=True)
        ts, ip, message = successes[0]
        base.update({"last_success_at": ts, "last_success_ip": ip, "last_success_message": message[:500]})
    base["failure_count"] = failures
    return base


def private_exposure_verified(serve: dict, funnel: dict) -> bool:
    """Return True only when the local evidence positively proves tailnet-only exposure."""
    return bool(
        serve.get("configured")
        and serve.get("tailnet_only") is True
        and serve.get("verification") == "tailnet-only"
        and funnel.get("verification") in {"off", "tailnet-only"}
        and not funnel.get("is_public")
    )


def safe_private_share_url(value: str, private_verified: bool) -> str:
    if not private_verified or not value:
        return ""
    try:
        parsed = urlparse(value)
    except Exception:
        return ""
    host = parsed.hostname or ""
    if parsed.scheme != "https" or not host.endswith(".ts.net"):
        return ""
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        return ""
    path = parsed.path or "/"
    if not path.startswith("/"):
        path = "/" + path
    return f"https://{host}{path}"


PAIR_URL_RE = re.compile(r"https://[^\s\"']+/pair#t=[^\s\"']+", re.I)
PAIR_FRAGMENT_RE = re.compile(r"(#t=)[A-Za-z0-9._~%+\-/=]+", re.I)
PAIR_FIELD_RE = re.compile(r"(pair_url\s*[=:]\s*[\"']?)[^\s\"']+", re.I)


def redact_pairing_secrets(value: str) -> str:
    """Redact pairing bearer credentials from any UI/log/export surface."""
    text = str(value or "")
    text = PAIR_FIELD_RE.sub(r"\1[REDACTED]", text)
    text = PAIR_URL_RE.sub("[REDACTED PAIRING URL]", text)
    text = PAIR_FRAGMENT_RE.sub(r"\1[REDACTED]", text)
    return text


def validate_pair_url(pair_url: str, serve_url: str) -> tuple[bool, str]:
    """Validate the LAN Share pairing credential without transforming it."""
    try:
        pair = urlparse(pair_url)
        serve = urlparse(serve_url)
    except Exception:
        return False, "Pairing URL is not a valid URL."

    if pair.scheme != "https" or serve.scheme != "https":
        return False, "Pairing requires HTTPS."
    if not pair.hostname or pair.hostname != serve.hostname:
        return False, "Pairing URL does not match the current private Serve host."
    if not pair.hostname.endswith(".ts.net"):
        return False, "Pairing URL is not a Tailscale HTTPS address."
    if pair.username or pair.password or pair.query:
        return False, "Pairing URL contains unexpected URL components."
    if pair.path.rstrip("/") != "/pair":
        return False, "Pairing URL path is unexpected."
    if not pair.fragment.startswith("t=") or len(pair.fragment) <= 10:
        return False, "Pairing URL is missing the one-time credential."
    return True, ""


def pair_command_support() -> dict:
    """
    Detect the LAN Share pairing feature without creating a credential.

    This must not depend on Quickshell's PATH.  `pair --help` is used as the
    non-secret capability probe; we never call `pair --json` during ordinary
    capability detection because that would mint a bearer credential.
    """
    binary = resolve_lan_share_binary()
    if not binary:
        return {
            "installed": False,
            "available": False,
            "cancel_supported": False,
            "binary": "",
            "status": "missing",
            "reason": "LAN Share is not installed.",
            "source": "explicit executable discovery",
        }

    result = run([binary, "pair", "--help"], timeout=4.0)
    help_text = f"{result.stdout}\n{result.stderr}"
    lower = help_text.lower()

    pair_supported = (
        result.returncode == 0
        or "--json" in help_text
        or "pair" in lower
    )

    # Some argparse/click implementations put subcommands only in top-level
    # help, so use that as a safe fallback.  This does not mint a token.
    if not pair_supported:
        top = run([binary, "--help"], timeout=4.0)
        top_text = f"{top.stdout}\n{top.stderr}".lower()
        pair_supported = bool(
            top.returncode == 0
            and re.search(r"(^|[\s,{])pair([\s,}]|$)", top_text)
        )
        if top_text:
            lower = lower + "\n" + top_text

    return {
        "installed": True,
        "available": bool(pair_supported),
        "cancel_supported": "--cancel" in lower,
        "binary": binary,
        "status": "supported" if pair_supported else "unsupported",
        "reason": (
            "QR pairing is supported."
            if pair_supported
            else "Installed LAN Share version does not support QR pairing."
        ),
        "source": f"{binary} pair --help",
    }


def lan_share_security_posture() -> dict:
    binary = resolve_lan_share_binary()
    if not binary:
        return {"ok": False, "security_revision": "", "reason": "LAN Share is not installed."}
    result = run([binary, "security", "--json"], timeout=4.0)
    if result.returncode != 0:
        return {"ok": False, "security_revision": "", "reason": "LAN Share security contract is unavailable."}
    try:
        payload = json.loads(result.stdout or "{}")
    except json.JSONDecodeError:
        return {"ok": False, "security_revision": "", "reason": "LAN Share security contract returned invalid JSON."}
    required = bool(
        payload.get("ok")
        and payload.get("security_revision") == "2.1-phase1b1"
        and payload.get("session_required") is True
        and payload.get("query_token_auth") is False
        and payload.get("pairing_requires_verified_private_serve") is True
        and int((payload.get("pin_rate_limit") or {}).get("client_max_failures") or 0) >= 3
        and ".ssh" in (payload.get("protected_paths") or [])
        and ".config" in (payload.get("protected_paths") or [])
    )
    payload["ok"] = required
    payload["reason"] = (
        "LAN Share Phase 1B.1 security contract verified."
        if required else "LAN Share security contract is incomplete."
    )
    return payload


def _simple_key_value_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return values
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip().lower()] = value.strip()
    return values


def wayvnc_security_posture() -> dict:
    """Verify local WayVNC auth, launcher and effective systemd command without exposing secrets."""
    cfg = _simple_key_value_file(WAYVNC_CONFIG)
    launcher_text = ""
    dropin_text = ""
    try:
        launcher_text = WAYVNC_LAUNCHER.read_text(encoding="utf-8")
    except OSError:
        pass
    try:
        dropin_text = WAYVNC_SECURITY_DROPIN.read_text(encoding="utf-8")
    except OSError:
        pass

    def mode(path: Path) -> int:
        try:
            return stat.S_IMODE(path.stat().st_mode)
        except OSError:
            return 0

    def owned(path: Path) -> bool:
        try:
            return path.stat().st_uid == UID
        except OSError:
            return False

    config_mode = mode(WAYVNC_CONFIG)
    key_mode = mode(WAYVNC_TLS_KEY)
    cert_mode = mode(WAYVNC_TLS_CERT)
    password = str(cfg.get("password") or "")
    username = str(cfg.get("username") or "")
    enable_auth = str(cfg.get("enable_auth") or "").lower() == "true"
    broken_crypto = str(cfg.get("allow_broken_crypto") or "").lower() == "true"
    relaxed = str(cfg.get("relax_encryption") or "").lower() == "true"

    expected_key = str(WAYVNC_TLS_KEY)
    expected_cert = str(WAYVNC_TLS_CERT)
    tls_files_ok = bool(
        WAYVNC_TLS_KEY.is_file()
        and WAYVNC_TLS_CERT.is_file()
        and cfg.get("private_key_file") == expected_key
        and cfg.get("certificate_file") == expected_cert
        and key_mode == 0o600
        and owned(WAYVNC_TLS_KEY)
        and owned(WAYVNC_TLS_CERT)
    )
    config_ok = bool(
        WAYVNC_CONFIG.is_file()
        and config_mode == 0o600
        and owned(WAYVNC_CONFIG)
        and enable_auth
        and username
        and len(password) >= 20
        and tls_files_ok
        and not broken_crypto
        and not relaxed
    )

    dynamic_launcher = bool(
        WAYVNC_LAUNCHER.is_file()
        and os.access(WAYVNC_LAUNCHER, os.X_OK)
        and "tailscale ip -4" in launcher_text
        and "arch-remote.conf" in launcher_text
        and "--config" in launcher_text
        and not re.search(r"\b100\.(?:\d{{1,3}}\.){{2}}\d{{1,3}}:5900\b", launcher_text)
    )
    secure_dropin = bool(
        WAYVNC_SECURITY_DROPIN.is_file()
        and "ExecStart=%h/.local/bin/wayvnc-remote" in dropin_text
        and "/usr/bin/wayvnc" not in dropin_text
    )

    effective_exec = ""
    systemctl = exe("systemctl")
    if systemctl:
        result = run([systemctl, "--user", "show", "wayvnc-remote", "--property=ExecStart", "--value"], timeout=4.0)
        if result.returncode == 0:
            effective_exec = result.stdout.strip()
    effective_launcher = "wayvnc-remote" in effective_exec and "100." not in effective_exec

    ok = bool(config_ok and dynamic_launcher and secure_dropin and effective_launcher)
    reasons = []
    if not config_ok:
        reasons.append("TLS/password authentication configuration is incomplete or has unsafe permissions")
    if not dynamic_launcher:
        reasons.append("WayVNC launcher does not dynamically resolve the Tailscale IPv4 address")
    if not secure_dropin:
        reasons.append("security drop-in does not force the canonical dynamic launcher")
    if not effective_launcher:
        reasons.append("effective systemd ExecStart is not the canonical launcher")

    cert_sha256 = ""
    if WAYVNC_TLS_CERT.is_file():
        try:
            cert_sha256 = hashlib.sha256(WAYVNC_TLS_CERT.read_bytes()).hexdigest()
        except OSError:
            pass

    return {
        "ok": ok,
        "security_revision": WAYVNC_SECURITY_REVISION,
        "auth_required": True,
        "auth_mode": "VeNCrypt/TLS + dedicated password",
        "username": username,
        "password_present": bool(password),
        "password_length_ok": len(password) >= 20,
        "config_path": str(WAYVNC_CONFIG),
        "config_mode": oct(config_mode) if config_mode else "missing",
        "private_key_path": str(WAYVNC_TLS_KEY),
        "private_key_mode": oct(key_mode) if key_mode else "missing",
        "certificate_path": str(WAYVNC_TLS_CERT),
        "certificate_mode": oct(cert_mode) if cert_mode else "missing",
        "certificate_sha256": cert_sha256,
        "dynamic_tailnet_bind": dynamic_launcher,
        "secure_dropin": secure_dropin,
        "effective_launcher": effective_launcher,
        "effective_exec": effective_exec[:800],
        "legacy_crypto_allowed": broken_crypto,
        "encryption_relaxed": relaxed,
        "tailnet_acl_verification": "external-unverified",
        "tailnet_acl_note": "Independent WayVNC authentication is enforced; Tailscale ACL policy remains a separate control-plane assurance.",
        "reason": "WayVNC TLS/password authentication and dynamic Tailscale binding verified." if ok else "; ".join(reasons),
    }


def private_share_pairing_readiness(state: dict) -> dict:
    share = state["services"]["lan_share"]
    serve = state["tailscale"]["serve"]
    funnel = state["tailscale"]["funnel"]
    support = pair_command_support()

    private_verified = private_exposure_verified(serve, funnel)
    safe_url = safe_private_share_url(serve.get("url", ""), private_verified)

    listeners = share.get("listeners") or []
    listener_ok = bool(listeners) and all(
        item.get("address") in {"127.0.0.1", "::1", "localhost"}
        and int(item.get("port", 0)) == 8000
        for item in listeners
    )

    upstream = str(serve.get("upstream") or "")
    upstream_ok = bool(
        re.match(
            r"^https?://(?:127\.0\.0\.1|localhost|\[::1\]):8000(?:/|$)",
            upstream,
        )
    )

    checks = {
        "service_ready": bool(share.get("ready")),
        "listener_ready": listener_ok,
        "serve_configured": bool(serve.get("configured")),
        "serve_tailnet_only": bool(serve.get("tailnet_only") is True)
        and serve.get("verification") == "tailnet-only",
        "funnel_private_verified": funnel.get("verification") in {"off", "tailnet-only"}
        and not bool(funnel.get("is_public")),
        "private_exposure_verified": private_verified,
        "serve_url_safe": bool(safe_url),
        "upstream_is_lan_share": upstream_ok,
        "qrencode_available": bool(exe("qrencode")),
        "pair_executable_found": bool(support.get("installed")),
        "pair_command_supported": bool(support.get("available")),
    }

    if not checks["service_ready"]:
        reason = "LAN Share is not ready."
    elif not checks["listener_ready"]:
        reason = "The expected loopback listener 127.0.0.1:8000 is not healthy."
    elif not checks["serve_configured"]:
        reason = "No Tailscale Serve route is configured."
    elif not checks["serve_tailnet_only"]:
        reason = "Tailscale Serve is not positively verified as tailnet-only."
    elif not checks["funnel_private_verified"]:
        reason = "Pairing is blocked until Funnel exposure is positively verified private/off."
    elif not checks["private_exposure_verified"] or not checks["serve_url_safe"]:
        reason = "Private Tailscale exposure could not be verified."
    elif not checks["upstream_is_lan_share"]:
        reason = "Tailscale Serve is not proxying to LAN Share on localhost:8000."
    elif not checks["pair_executable_found"]:
        reason = "LAN Share is not installed."
    elif not checks["pair_command_supported"]:
        reason = "Installed LAN Share version does not support QR pairing."
    elif not checks["qrencode_available"]:
        reason = "QR encoder is unavailable."
    else:
        reason = "Ready for one-scan pairing."

    return {
        "available": all(checks.values()),
        "reason": reason,
        "checks": checks,
        "serve_url": safe_url,
        "pair_binary": str(support.get("binary") or ""),
        "pair_support_status": str(support.get("status") or "missing"),
    }


def pairing_create() -> dict:
    """Create a short-lived one-time pairing QR without persisting the secret."""
    state = snapshot(False)
    readiness = private_share_pairing_readiness(state)
    if not readiness["available"]:
        return {
            "error": True,
            "ok": False,
            "state": "error",
            "message": "Cannot generate pairing QR — " + readiness["reason"],
            "reason": readiness["reason"],
        }

    support = pair_command_support()
    binary = str(support.get("binary") or "")
    qrencode = exe("qrencode")
    if not binary or not support.get("available") or not qrencode:
        return {"error": True, "ok": False, "state": "error", "message": "Pairing dependencies are unavailable."}

    # Never log stdout from this command: it contains the temporary bearer credential.
    result = run([binary, "pair", "--json"], timeout=8.0)
    if result.returncode != 0:
        return {
            "error": True,
            "ok": False,
            "state": "error",
            "message": "Pairing generation failed. LAN Share rejected the pairing request.",
        }

    raw = result.stdout
    try:
        payload = json.loads(raw)
    except Exception:
        raw = ""
        return {
            "error": True,
            "ok": False,
            "state": "error",
            "message": "Pairing generation failed. LAN Share returned invalid machine-readable state.",
        }
    raw = ""

    pair_url = str(payload.get("pair_url") or "")
    valid_url, url_error = validate_pair_url(pair_url, readiness["serve_url"])
    if not valid_url:
        pair_url = ""
        return {"error": True, "ok": False, "state": "error", "message": "Pairing generation failed. " + url_error}

    try:
        expires_at = int(payload.get("expires_at"))
        expires_in = int(payload.get("expires_in"))
    except Exception:
        pair_url = ""
        return {"error": True, "ok": False, "state": "error", "message": "Pairing generation failed. Expiration metadata is invalid."}

    single_use = payload.get("single_use") is True
    now = int(time.time())
    if not single_use:
        pair_url = ""
        return {"error": True, "ok": False, "state": "error", "message": "Pairing generation failed. LAN Share did not mark the credential single-use."}
    if expires_at <= now or expires_in <= 0 or expires_at > now + 900 or expires_in > 900:
        pair_url = ""
        return {"error": True, "ok": False, "state": "error", "message": "Pairing generation failed. Credential lifetime is not short-lived."}

    # Encode from stdin: secret is not placed in argv and no QR file is written.
    try:
        qr = subprocess.run(
            [qrencode, "-o", "-", "-t", "PNG", "-s", "7", "-m", "2"],
            input=pair_url.encode("utf-8"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5.0,
            check=False,
        )
    except Exception:
        pair_url = ""
        return {"error": True, "ok": False, "state": "error", "message": "Pairing QR rendering failed."}

    if qr.returncode != 0 or not qr.stdout:
        pair_url = ""
        return {"error": True, "ok": False, "state": "error", "message": "Pairing QR rendering failed."}

    import base64
    qr_data_url = "data:image/png;base64," + base64.b64encode(qr.stdout).decode("ascii")

    record_activity(
        "pairing",
        "Private Share pairing generated",
        f"Single-use credential created; expires in {expires_in}s.",
        "info",
    )

    pair_url = ""
    return {
        "ok": True,
        "state": "ready",
        "message": "One-scan pairing QR ready",
        "expires_at": expires_at,
        "expires_in": expires_in,
        "single_use": True,
        "qr_data_url": qr_data_url,
        "server_cancel_supported": pair_command_support()["cancel_supported"],
    }


def pairing_cancel() -> dict:
    """Revoke server-side when supported; otherwise report local dismissal honestly."""
    support = pair_command_support()
    binary = str(support.get("binary") or "")
    if not support.get("cancel_supported") or not binary:
        record_activity(
            "pairing",
            "Private Share pairing dismissed",
            "QR hidden locally; backend token was not claimed revoked and will expire or be replaced.",
            "info",
        )
        return {
            "ok": True,
            "state": "cancelled",
            "backend_revoked": False,
            "message": "Pairing dismissed locally. The server credential will expire automatically or be invalidated by the next QR.",
        }

    result = run([binary, "pair", "--cancel", "--json"], timeout=6.0)
    if result.returncode != 0:
        return {
            "error": True,
            "ok": False,
            "state": "error",
            "message": "Could not revoke the pending pairing on LAN Share.",
        }

    record_activity(
        "pairing",
        "Private Share pairing cancelled",
        "Pending pairing credential revoked server-side.",
        "info",
    )
    return {
        "ok": True,
        "state": "cancelled",
        "backend_revoked": True,
        "message": "Pairing cancelled and revoked",
    }


def human_bytes(value: int | float) -> str:
    value = float(value)
    for suffix in ("B", "KB", "MB", "GB", "TB"):
        if value < 1024.0 or suffix == "TB":
            if suffix in {"B", "KB"}:
                return f"{value:.0f} {suffix}"
            return f"{value:.1f} {suffix}"
        value /= 1024.0
    return "0 B"


def human_seconds(seconds: int | float) -> str:
    seconds = max(0, int(seconds))
    if seconds < 60:
        return f"{seconds}s"
    minutes, second = divmod(seconds, 60)
    if minutes < 60:
        return f"{minutes}m {second:02d}s"
    hours, minute = divmod(minutes, 60)
    if hours < 24:
        return f"{hours}h {minute:02d}m"
    days, hour = divmod(hours, 24)
    return f"{days}d {hour}h"


def parse_key_values(text: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in text.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def parse_config_words(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except Exception:
        return values

    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith("["):
            continue
        if "=" in line:
            key, value = line.split("=", 1)
            values[key.strip().lower()] = value.strip()
            continue
        parts = line.split(None, 1)
        if len(parts) == 2:
            values[parts[0].lower()] = parts[1].strip()
    return values


def service_state(name: str, scope: str, expected_running: bool) -> dict:
    systemctl = exe("systemctl")
    expected_state = "running" if expected_running else "on-demand"
    base = {
        "name": name, "scope": scope, "loaded": False, "configured": False,
        "active": False, "running": False, "active_state": "unknown", "sub_state": "unknown",
        "enabled_state": "unknown", "enabled": False, "boot_enabled": False,
        "expected_running": expected_running, "expected_state": expected_state,
        "status": "unavailable", "health": "unavailable", "pid": 0, "restarts": 0,
        "started_at": "", "fragment_path": "", "memory_bytes": 0, "memory": "—",
        "cpu_time": "—", "result": "unknown", "exec_main_status": "unknown",
    }
    if not systemctl:
        return base

    command = [systemctl]
    if scope == "user":
        command.append("--user")
    command += [
        "show", name, "--no-pager",
        "--property=LoadState,ActiveState,SubState,UnitFileState,MainPID,NRestarts,ActiveEnterTimestamp,FragmentPath,MemoryCurrent,CPUUsageNSec,Result,ExecMainStatus",
    ]
    result = run(command, timeout=4.0)
    if result.returncode != 0 and not result.stdout.strip():
        return base

    values = parse_key_values(result.stdout)
    loaded = values.get("LoadState") == "loaded"
    active_state = values.get("ActiveState", "unknown")
    running = active_state == "active"
    enabled_state = values.get("UnitFileState", "unknown")
    boot_enabled = enabled_state in {"enabled", "enabled-runtime", "linked", "static"}

    def integer(key):
        try:
            return int(values.get(key, "0") or 0)
        except Exception:
            return 0

    pid = integer("MainPID")
    restarts = integer("NRestarts")
    memory_bytes = integer("MemoryCurrent")
    cpu_ns = integer("CPUUsageNSec")

    if not loaded:
        health = "unavailable"
    elif expected_running and running:
        health = "healthy"
    elif expected_running and not running:
        health = "degraded"
    elif not expected_running and not running:
        health = "expected-inactive"
    else:
        health = "healthy"

    status = "unavailable" if not loaded else "running" if running else "failed" if active_state == "failed" else "inactive"
    return {
        "name": name, "scope": scope, "loaded": loaded, "configured": loaded,
        "active": running, "running": running, "active_state": active_state,
        "sub_state": values.get("SubState", "unknown"), "enabled_state": enabled_state,
        "enabled": boot_enabled, "boot_enabled": boot_enabled, "expected_running": expected_running,
        "expected_state": expected_state, "status": status, "health": health, "pid": pid,
        "restarts": restarts, "started_at": values.get("ActiveEnterTimestamp", ""),
        "fragment_path": values.get("FragmentPath", ""), "memory_bytes": memory_bytes,
        "memory": human_bytes(memory_bytes) if memory_bytes > 0 else "—",
        "cpu_time": human_seconds(cpu_ns / 1_000_000_000) if cpu_ns > 0 else "—",
        "result": values.get("Result", "unknown"), "exec_main_status": values.get("ExecMainStatus", "unknown"),
    }


def services_state() -> dict:
    return {
        "sshd": service_state("sshd", "system", True),
        "tailscaled": service_state("tailscaled", "system", True),
        "lan_share": service_state("lan-share", "user", False),
        "wayvnc": service_state("wayvnc-remote", "user", False),
    }


def normalize_peer(peer: dict, self_peer=False) -> dict:
    ips = peer.get("TailscaleIPs") or peer.get("Addresses") or []
    if not isinstance(ips, list):
        ips = []
    return {
        "hostname": str(peer.get("HostName") or peer.get("ComputedName") or peer.get("DNSName") or "Unknown"),
        "dns_name": str(peer.get("DNSName") or "").rstrip("."),
        "os": str(peer.get("OS") or "unknown"),
        "addresses": [str(value) for value in ips],
        "online": bool(peer.get("Online", self_peer)),
        "active": bool(peer.get("Active", peer.get("Online", self_peer))),
        "last_seen": str(peer.get("LastSeen") or ""),
        "last_handshake": str(peer.get("LastHandshake") or ""),
        "is_self": bool(self_peer),
    }


def parse_serve_json(payload) -> tuple[str, str, str]:
    if not isinstance(payload, dict):
        return "", "", ""
    web = payload.get("Web") or {}
    if not isinstance(web, dict):
        return "", "", ""
    for host_port, web_config in web.items():
        if not isinstance(web_config, dict):
            continue
        handlers = web_config.get("Handlers") or {}
        if not isinstance(handlers, dict):
            continue
        for route, handler in handlers.items():
            if not isinstance(handler, dict):
                continue
            proxy = handler.get("Proxy") or handler.get("proxy") or ""
            if proxy:
                host = str(host_port).split(":", 1)[0]
                return host, str(route), str(proxy)
    return "", "", ""


def http_probe(url: str, timeout=1.5) -> dict:
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"}:
        return {"tested": False, "reachable": False, "status_code": 0, "error": "unsupported scheme"}
    host = parsed.hostname or ""
    if host not in {"127.0.0.1", "localhost", "::1"}:
        return {"tested": False, "reachable": False, "status_code": 0, "error": "non-local upstream"}
    try:
        request = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return {"tested": True, "reachable": True, "status_code": int(response.getcode() or 0), "error": ""}
    except urllib.error.HTTPError as error:
        return {"tested": True, "reachable": True, "status_code": int(error.code or 0), "error": ""}
    except Exception as error:
        return {"tested": True, "reachable": False, "status_code": 0, "error": str(error)}


def tailscale_status() -> dict:
    binary = exe("tailscale")
    base = {
        "available": bool(binary),
        "active": False,
        "running": False,
        "connected": False,
        "backend_state": "unavailable",
        "hostname": "",
        "dns_name": "",
        "ipv4": "",
        "ipv6": "",
        "magic_dns": False,
        "devices": [],
        "phone": None,
        "health": "unavailable",
        "health_messages": [],
    }
    if not binary:
        return base

    result = run([binary, "status", "--json"], timeout=6.0)
    try:
        payload = json.loads(result.stdout) if result.returncode == 0 else {}
    except Exception:
        payload = {}
    if not isinstance(payload, dict):
        return base

    self_peer = payload.get("Self") or {}
    ips = self_peer.get("TailscaleIPs") or payload.get("TailscaleIPs") or []
    backend = str(payload.get("BackendState") or "unknown")
    connected = backend == "Running"
    dns_name = str(self_peer.get("DNSName") or "").rstrip(".")

    devices = [normalize_peer(self_peer, True)] if self_peer else []
    peers = payload.get("Peer") or {}
    peers = peers.values() if isinstance(peers, dict) else peers
    if isinstance(peers, (list, tuple)) or hasattr(peers, "__iter__"):
        for peer in peers:
            if isinstance(peer, dict):
                devices.append(normalize_peer(peer))

    phone = None
    for device in devices:
        searchable = f"{device['hostname']} {device['dns_name']} {device['os']}".lower()
        if "android" in searchable or "s22" in searchable:
            phone = device
            break

    health_messages = payload.get("Health") or []
    if not isinstance(health_messages, list):
        health_messages = [str(health_messages)]

    base.update(
        {
            "active": connected,
            "running": connected,
            "connected": connected,
            "backend_state": backend,
            "hostname": str(self_peer.get("HostName") or socket.gethostname()),
            "dns_name": dns_name,
            "ipv4": next((str(value) for value in ips if "." in str(value)), ""),
            "ipv6": next((str(value) for value in ips if ":" in str(value)), ""),
            "magic_dns": bool(payload.get("MagicDNSSuffix") or (payload.get("CurrentTailnet") or {}).get("MagicDNSEnabled")),
            "devices": devices,
            "phone": phone,
            "health": "degraded" if health_messages else "healthy" if connected else "degraded",
            "health_messages": [str(value) for value in health_messages],
        }
    )
    return base


def serve_state(binary: str | None) -> dict:
    state = {
        "available": bool(binary),
        "active": False,
        "configured": False,
        "url": "",
        "host": "",
        "route_path": "",
        "upstream": "",
        "upstream_tested": False,
        "upstream_reachable": False,
        "upstream_status": 0,
        "tailnet_only": False,
        "is_public": False,
        "verification": "unavailable",
        "health": "inactive",
        "source": "tailscale serve status",
        "raw": "",
    }
    if not binary:
        return state

    json_result = run([binary, "serve", "status", "--json"], timeout=5.0)
    text_result = run([binary, "serve", "status"], timeout=5.0)
    raw = (text_result.stdout or text_result.stderr).strip()
    state["raw"] = raw[:5000]

    try:
        payload = json.loads(json_result.stdout) if json_result.returncode == 0 else None
    except Exception:
        payload = None

    host, route, upstream = parse_serve_json(payload)
    if host:
        state["host"] = host
        state["url"] = f"https://{host}"
    else:
        match = re.search(r"https://([A-Za-z0-9._-]+)(?::\d+)?/?", raw)
        if match:
            state["host"] = match.group(1)
            state["url"] = match.group(0).rstrip("/")

    if route:
        state["route_path"] = route if route.startswith("/") else "/" + route
    if upstream:
        state["upstream"] = upstream
    elif raw:
        match = re.search(r"proxy\s+(https?://[^\s]+)", raw)
        if match:
            state["upstream"] = match.group(1)

    configured = bool(state["url"] or state["upstream"] or (isinstance(payload, dict) and (payload.get("TCP") or payload.get("Web"))))
    lower = raw.lower()
    if "no serve config" in lower or "not configured" in lower:
        configured = False

    state["configured"] = configured
    state["active"] = configured
    if not configured:
        state["tailnet_only"] = False
        state["verification"] = "off"
    elif "tailnet only" in lower:
        state["tailnet_only"] = True
        state["verification"] = "tailnet-only"
    elif "available on the internet" in lower or "funnel on" in lower:
        state["tailnet_only"] = False
        state["is_public"] = True
        state["verification"] = "public"
    else:
        # Configured does not itself prove privacy. Unknown parser/output states
        # must never be promoted to tailnet-only.
        state["tailnet_only"] = False
        state["verification"] = "unknown"

    if state["upstream"]:
        probe = http_probe(state["upstream"])
        state["upstream_tested"] = probe["tested"]
        state["upstream_reachable"] = probe["reachable"]
        state["upstream_status"] = probe["status_code"]

    if not configured:
        state["health"] = "inactive"
    elif state["verification"] == "public":
        state["health"] = "critical"
    elif state["verification"] != "tailnet-only":
        state["health"] = "unknown"
    elif state["upstream_tested"] and not state["upstream_reachable"]:
        state["health"] = "degraded"
    else:
        state["health"] = "healthy"
    return state


def funnel_state(binary: str | None) -> dict:
    state = {
        "available": bool(binary),
        "active": False,
        "configured": False,
        "is_public": False,
        "url": "",
        "verification": "unavailable",
        "health": "unavailable",
        "source": "tailscale funnel status (text is authoritative for public/private classification)",
        "raw": "",
    }
    if not binary:
        return state

    result = run([binary, "funnel", "status"], timeout=5.0)
    raw = (result.stdout or result.stderr).strip()
    state["raw"] = raw[:5000]
    lower = raw.lower()

    match = re.search(r"https://[A-Za-z0-9._-]+(?::\d+)?/?", raw)
    if match:
        state["url"] = match.group(0).rstrip("/")

    # Important: on current Tailscale releases `funnel status --json` can expose
    # the same underlying serve config even when the route is tailnet-only.
    # Public/private classification therefore comes from the human status marker.
    if "tailnet only" in lower:
        state.update({"active": False, "configured": False, "is_public": False, "verification": "tailnet-only", "health": "healthy"})
    elif "available on the internet" in lower or "funnel on" in lower or "public" in lower:
        state.update({"active": True, "configured": True, "is_public": True, "verification": "public", "health": "critical"})
    elif "no funnel" in lower or "not configured" in lower:
        state.update({"active": False, "configured": False, "is_public": False, "verification": "off", "health": "healthy"})
    else:
        state.update({"active": False, "configured": False, "is_public": False, "verification": "unknown", "health": "unknown"})
    return state


def tailscale_state() -> dict:
    binary = exe("tailscale")
    base = tailscale_status()
    base["serve"] = serve_state(binary)
    base["funnel"] = funnel_state(binary)
    return base


def split_endpoint(value: str):
    value = value.strip()
    match = re.match(r"^\[(.*)\]:(\d+)$", value) if value.startswith("[") else re.match(r"^(.*):(\d+)$", value)
    if not match:
        return "", 0
    try:
        return match.group(1), int(match.group(2))
    except ValueError:
        return "", 0


def listeners_state(tailscale: dict) -> list[dict]:
    binary = exe("ss")
    if not binary:
        return []
    result = run([binary, "-H", "-lntp"], timeout=5.0)
    if result.returncode != 0:
        result = run([binary, "-H", "-lnt"], timeout=5.0)

    tail_addrs = {value for value in (tailscale.get("ipv4", ""), tailscale.get("ipv6", "")) if value}
    entries = []
    for line in result.stdout.splitlines():
        columns = line.split()
        if len(columns) < 4:
            continue
        address, port = split_endpoint(columns[3])
        if port <= 0:
            continue
        process_match = re.search(r'\(\("([^"]+)",pid=(\d+)', line)
        process = process_match.group(1) if process_match else ""
        pid = int(process_match.group(2)) if process_match else 0

        if address in {"127.0.0.1", "::1", "localhost"}:
            bind_scope = "loopback"
        elif address in {"0.0.0.0", "::", "*"}:
            bind_scope = "all-interfaces"
        elif address in tail_addrs or address.startswith("100."):
            bind_scope = "tailnet"
        else:
            bind_scope = "bound"

        entries.append(
            {
                "protocol": "tcp",
                "address": address,
                "port": port,
                "endpoint": columns[3],
                "scope": "localhost" if bind_scope == "loopback" else "tailscale" if bind_scope == "tailnet" else bind_scope,
                "bind_scope": bind_scope,
                "process": process,
                "pid": pid,
            }
        )
    return entries


def classify_listener(entry: dict, tailscale: dict) -> dict:
    port = int(entry["port"])
    bind_scope = entry["bind_scope"]
    result = dict(entry)
    result.update(
        {
            "service": entry["process"] or f"TCP {port}",
            "reachable_scope": "Unknown",
            "expected_policy": "No explicit policy",
            "policy_status": "informational",
            "finding": "info",
            "group": "other",
        }
    )

    if port == 22:
        result.update(
            {
                "service": "SSH",
                "reachable_scope": "LAN + tailnet" if bind_scope == "all-interfaces" else "Bound network",
                "expected_policy": "LAN + tailnet is intentional for recovery",
                "policy_status": "expected",
                "finding": "healthy",
                "group": "local-network",
            }
        )
        return result

    if port == 8000:
        good = bind_scope == "loopback"
        result.update(
            {
                "service": "LAN Share",
                "reachable_scope": "Loopback only" if good else "LAN / broader",
                "expected_policy": "Loopback only (127.0.0.1:8000)",
                "policy_status": "expected" if good else "unexpected",
                "finding": "healthy" if good else "critical",
                "group": "loopback" if good else "unexpected",
            }
        )
        return result

    if port == 5900:
        tail_addrs = {value for value in (tailscale.get("ipv4", ""), tailscale.get("ipv6", "")) if value}
        good = bind_scope == "tailnet" or entry["address"] in tail_addrs
        result.update(
            {
                "service": "WayVNC",
                "reachable_scope": "Tailnet only" if good else "LAN / broader",
                "expected_policy": "Tailscale address only",
                "policy_status": "expected" if good else "unexpected",
                "finding": "healthy" if good else "critical",
                "group": "private-network" if good else "unexpected",
            }
        )
        return result

    if port == 443 and bind_scope == "tailnet":
        result.update(
            {
                "service": "Tailscale HTTPS",
                "reachable_scope": "Tailnet",
                "expected_policy": "Private tailnet",
                "policy_status": "expected",
                "finding": "healthy",
                "group": "private-network",
            }
        )
        return result

    if bind_scope == "loopback":
        result.update(
            {
                "reachable_scope": "Loopback only",
                "expected_policy": "Local application",
                "group": "loopback",
            }
        )
    elif bind_scope == "tailnet":
        result.update(
            {
                "reachable_scope": "Tailnet",
                "expected_policy": "Private network",
                "group": "private-network",
            }
        )
    elif bind_scope == "all-interfaces":
        result.update(
            {
                "reachable_scope": "LAN + other local interfaces",
                "expected_policy": "Unclassified all-interface listener",
                "policy_status": "review",
                "finding": "warning",
                "group": "other",
            }
        )
    else:
        result.update(
            {
                "reachable_scope": "Bound network",
                "expected_policy": "Unclassified listener",
                "group": "other",
            }
        )
    return result


def exposure_state(listeners: list[dict], tailscale: dict) -> dict:
    classified = [classify_listener(item, tailscale) for item in listeners]
    groups = {
        "private_network": [item for item in classified if item["group"] == "private-network"],
        "local_network": [item for item in classified if item["group"] == "local-network"],
        "loopback_only": [item for item in classified if item["group"] == "loopback"],
        "unexpected": [item for item in classified if item["group"] == "unexpected"],
        "other": [item for item in classified if item["group"] == "other"],
    }
    public = bool(tailscale["funnel"]["is_public"])
    funnel_verification = str(tailscale["funnel"].get("verification") or "unknown")
    exposure_verified = funnel_verification in {"off", "tailnet-only", "public"}
    if public:
        summary = "Application-level public exposure detected"
    elif exposure_verified:
        summary = "No application-level public exposure detected"
    else:
        summary = "Application-level public exposure is not verified"
    return {
        "listeners": classified,
        "groups": groups,
        "unexpected_count": len(groups["unexpected"]),
        "application_public_exposure_detected": public,
        "application_public_exposure_verified": exposure_verified,
        "router_nat_verified": False,
        "summary": summary,
        "router_note": "Router/NAT exposure not verified.",
    }


def ssh_state() -> dict:
    configured = parse_config_words(SSH_DROPIN)
    attempt = run_sshd_effective(False)
    effective = {}
    effective_verified = False
    effective_error = attempt.get("error", "")
    source = ""
    checked_at = 0.0

    if attempt["ok"]:
        effective = attempt["values"]
        effective_verified = True
        source = attempt["source"]
        checked_at = time.time()
        save_ssh_effective_cache(effective, source)
    else:
        cached = cached_ssh_effective()
        if cached["ok"]:
            effective = cached["values"]
            effective_verified = True
            source = cached["source"] + " (cached; SSH config/runtime provenance unchanged)"
            checked_at = cached["checked_at"]
        else:
            source = "hardened SSH drop-in (configured state only)"

    configured_view = {
        "permit_root_login": configured.get("permitrootlogin", "unknown"),
        "pubkey_authentication": configured.get("pubkeyauthentication", "unknown"),
        "password_authentication": configured.get("passwordauthentication", "unknown"),
        "kbd_interactive_authentication": configured.get("kbdinteractiveauthentication", "unknown"),
        "allow_users": configured.get("allowusers", ""),
    }
    effective_view = {
        "permit_root_login": effective.get("permitrootlogin", "unknown"),
        "pubkey_authentication": effective.get("pubkeyauthentication", "unknown"),
        "password_authentication": effective.get("passwordauthentication", "unknown"),
        "kbd_interactive_authentication": effective.get("kbdinteractiveauthentication", "unknown"),
        "allow_users": effective.get("allowusers", ""),
    }
    values = effective_view if effective_verified else configured_view

    mode = ""
    if AUTHORIZED_KEYS.is_file():
        try:
            mode = oct(stat.S_IMODE(AUTHORIZED_KEYS.stat().st_mode))
        except Exception:
            pass

    result = {
        "source": source,
        "effective_verified": effective_verified,
        "effective_error": effective_error,
        "effective_checked_at": checked_at,
        "verification_available": bool(exe("pkexec") or attempt["ok"]),
        "configured": configured_view,
        "effective": effective_view,
        "dropin_path": str(SSH_DROPIN),
        "dropin_exists": SSH_DROPIN.is_file(),
        "permit_root_login": values["permit_root_login"],
        "pubkey_authentication": values["pubkey_authentication"],
        "password_authentication": values["password_authentication"],
        "kbd_interactive_authentication": values["kbd_interactive_authentication"],
        "allow_users": values["allow_users"],
        "authorized_keys_exists": AUTHORIZED_KEYS.is_file(),
        "authorized_keys_mode": mode,
    }
    result["key_only"] = result["pubkey_authentication"].lower() == "yes" and result["password_authentication"].lower() == "no"
    result["root_disabled"] = result["permit_root_login"].lower() == "no"
    result["secure"] = result["effective_verified"] and result["key_only"] and result["root_disabled"] and result["kbd_interactive_authentication"].lower() == "no"
    return result


def ssh_host_fingerprint() -> dict:
    keygen = exe("ssh-keygen")
    if not keygen or not SSH_HOST_ED25519_PUB.is_file():
        return {"available": False, "algorithm": "", "fingerprint": "", "source": ""}
    result = run([keygen, "-lf", str(SSH_HOST_ED25519_PUB), "-E", "sha256"], timeout=4.0)
    if result.returncode != 0:
        return {"available": False, "algorithm": "", "fingerprint": "", "source": ""}
    fingerprint = next((part for part in result.stdout.strip().split() if part.startswith("SHA256:")), "")
    return {"available": bool(fingerprint), "algorithm": "ED25519", "fingerprint": fingerprint, "source": str(SSH_HOST_ED25519_PUB)}


def interfaces_state() -> list[dict]:
    binary = exe("ip")
    if not binary:
        return []
    result = run([binary, "-j", "addr", "show"], timeout=4.0)
    try:
        payload = json.loads(result.stdout) if result.returncode == 0 else []
    except Exception:
        payload = []
    interfaces = []
    for item in payload:
        name = str(item.get("ifname") or "")
        if not name:
            continue
        addresses = [str(entry.get("local")) for entry in item.get("addr_info", []) if entry.get("local")]
        interfaces.append(
            {
                "name": name,
                "state": str(item.get("operstate") or "UNKNOWN"),
                "mac": str(item.get("address") or ""),
                "addresses": addresses,
                "wireless": Path(f"/sys/class/net/{name}/wireless").exists(),
                "physical": Path(f"/sys/class/net/{name}/device").exists(),
                "tailscale": name.startswith("tailscale"),
                "loopback": name == "lo",
            }
        )
    return interfaces


def wake_state(interfaces: list[dict]) -> dict:
    ethernet = {
        "interface_name": "",
        "mac": "",
        "supported": False,
        "enabled": False,
        "capability": "unknown",
        "configured": "unknown",
        "raw_supported": "",
        "raw_current": "",
        "tested": False,
        "test_status": "untested",
        "error": "",
    }
    wifi = {
        "interface_name": "",
        "phy": "",
        "mac": "",
        "supported": False,
        "enabled": False,
        "capability": "unknown",
        "configured": "unknown",
        "persistent": WOWLAN_FILE.is_file(),
        "tested": False,
        "test_status": "untested",
        "error": "",
    }

    wired_candidates = [item for item in interfaces if item["physical"] and not item["wireless"] and not item["loopback"] and not item["tailscale"]]
    if not wired_candidates:
        wired_candidates = [item for item in interfaces if not item["wireless"] and not item["loopback"] and not item["tailscale"]]
    if wired_candidates:
        chosen = wired_candidates[0]
        ethernet["interface_name"] = chosen["name"]
        ethernet["mac"] = chosen["mac"]

    wireless_candidates = [item for item in interfaces if item["wireless"]]
    if wireless_candidates:
        chosen = wireless_candidates[0]
        wifi["interface_name"] = chosen["name"]
        wifi["mac"] = chosen["mac"]

    ethtool = exe("ethtool")
    if ethernet["interface_name"] and ethtool:
        result = run([ethtool, ethernet["interface_name"]], timeout=5.0)
        support = re.search(r"Supports Wake-on:\s*(\S+)", result.stdout)
        current = re.search(r"Wake-on:\s*(\S+)", result.stdout)
        ethernet["raw_supported"] = support.group(1) if support else ""
        ethernet["raw_current"] = current.group(1) if current else ""
        if support:
            ethernet["capability"] = "supported" if "g" in support.group(1) else "unsupported"
            ethernet["supported"] = "g" in support.group(1)
        if current:
            ethernet["configured"] = "enabled" if "g" in current.group(1) else "disabled"
            ethernet["enabled"] = "g" in current.group(1)
        if not support and not current:
            message = (result.stderr or result.stdout).strip()[:500]
            ethernet["error"] = message or "ethtool did not expose Wake-on fields for the disconnected interface"

    if wifi["interface_name"]:
        try:
            phy = Path(f"/sys/class/net/{wifi['interface_name']}/phy80211").resolve().name
        except Exception:
            phy = ""
        wifi["phy"] = phy
        iw = exe("iw")
        if phy and iw:
            info_result = run([iw, "phy", phy, "info"], timeout=5.0)
            show_result = run([iw, "phy", phy, "wowlan", "show"], timeout=5.0)
            info = info_result.stdout.lower()
            show = show_result.stdout.lower()
            if info:
                wifi["capability"] = "supported" if "magic packet" in info else "unsupported"
                wifi["supported"] = "magic packet" in info
            if show:
                wifi["configured"] = "enabled" if "magic packet" in show else "disabled"
                wifi["enabled"] = "magic packet" in show
            if not info and not show:
                wifi["error"] = (info_result.stderr or show_result.stderr).strip()[:500]

    return {"ethernet": ethernet, "wifi": wifi, "dispatcher_path": str(WOWLAN_FILE)}


def linger_state() -> dict:
    binary = exe("loginctl")
    if not binary:
        return {"enabled": False, "value": "unknown", "source": "loginctl unavailable"}
    result = run([binary, "show-user", USER, "-p", "Linger", "--value"], timeout=4.0)
    value = result.stdout.strip() or "unknown"
    return {"enabled": value.lower() == "yes", "value": value, "source": "loginctl show-user"}


def parse_epoch(timestamp_text: str) -> float:
    date = exe("date")
    if not date or not timestamp_text:
        return 0.0
    result = run([date, "-d", timestamp_text, "+%s"], timeout=3.0)
    try:
        return float(result.stdout.strip())
    except Exception:
        return 0.0


def lid_state() -> dict:
    configured = parse_config_words(LID_DROPIN)
    configured_state = {
        "battery": configured.get("handlelidswitch", "unknown"),
        "external_power": configured.get("handlelidswitchexternalpower", "unknown"),
        "docked": configured.get("handlelidswitchdocked", "unknown"),
    }
    file_mtime = LID_DROPIN.stat().st_mtime if LID_DROPIN.is_file() else 0.0
    start_text = ""
    systemctl = exe("systemctl")
    if systemctl:
        start_text = run([systemctl, "show", "systemd-logind.service", "--property=ActiveEnterTimestamp", "--value"], timeout=4.0).stdout.strip()
    logind_epoch = parse_epoch(start_text)
    pending = bool(file_mtime and logind_epoch and file_mtime > logind_epoch)
    effective_verified = bool(LID_DROPIN.is_file() and logind_epoch and not pending)
    return {
        "exists": LID_DROPIN.is_file(),
        "path": str(LID_DROPIN),
        "battery": configured_state["battery"],
        "external_power": configured_state["external_power"],
        "docked": configured_state["docked"],
        "configured": configured_state,
        "effective": {
            "verified": effective_verified,
            "battery": configured_state["battery"] if effective_verified else "unverified",
            "external_power": configured_state["external_power"] if effective_verified else "unverified",
            "docked": configured_state["docked"] if effective_verified else "unverified",
            "source": "logind start timestamp compared with drop-in mtime",
        },
        "pending_reboot": pending,
        "status": "configured-pending-reboot" if pending else "configured" if LID_DROPIN.is_file() else "unavailable",
        "logind_started_at": start_text,
    }


def host_state() -> dict:
    disk = shutil.disk_usage(HOME)
    disk_percent = round(disk.used / disk.total * 100.0, 1) if disk.total else 0.0
    try:
        uptime = float(Path("/proc/uptime").read_text().split()[0])
    except Exception:
        uptime = 0
    try:
        load = " · ".join(f"{value:.2f}" for value in os.getloadavg())
    except Exception:
        load = "—"
    return {
        "hostname": socket.gethostname(),
        "user": USER,
        "home": str(HOME),
        "kernel": run(["uname", "-r"], timeout=2.0).stdout.strip(),
        "uptime": human_seconds(uptime),
        "load": load,
        "storage": {"percent": disk_percent, "free": human_bytes(disk.free), "total": human_bytes(disk.total)},
    }


def graphical_state() -> dict:
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{UID}"))
    sockets = sorted(path.name for path in runtime.glob("wayland-*") if path.exists())
    hyprctl = exe("hyprctl")
    available = False
    if hyprctl:
        result = run([hyprctl, "-j", "monitors"], timeout=4.0)
        try:
            payload = json.loads(result.stdout)
            available = isinstance(payload, list) and bool(payload)
        except Exception:
            pass
    return {
        "hyprland_available": available,
        "wayland_display": os.environ.get("WAYLAND_DISPLAY", "") or (sockets[0] if sockets else ""),
        "wayland_sockets": sockets,
    }


def slow_state(force=False) -> dict:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    if not force and SLOW_CACHE.is_file():
        cached = load_json(SLOW_CACHE, {})
        age = time.time() - float(cached.get("checked_at", 0) or 0)
        if cached and age < SLOW_TTL:
            # Effective SSH proof can change independently through an explicit verification action.
            cached["ssh"] = ssh_state()
            return cached

    interfaces = interfaces_state()
    payload = {
        "checked_at": time.time(),
        "ssh": ssh_state(),
        "ssh_host_fingerprint": ssh_host_fingerprint(),
        "ssh_auth": ssh_recent_auth_state(),
        "interfaces": interfaces,
        "wake": wake_state(interfaces),
        "linger": linger_state(),
        "lid": lid_state(),
    }
    atomic_json(SLOW_CACHE, payload)
    return payload


def check(check_id: str, category: str, severity: str, status: str, title: str, expected: str,
          detected: str, source: str, explanation: str, remediation: str,
          repair_available=False, privilege="none", verification_scope="local",
          confidence="verified", evidence_sources=None) -> dict:
    return {
        "id": check_id,
        "category": category,
        "severity": severity,
        "status": status,
        "title": title,
        "expected": str(expected),
        "detected": str(detected),
        "current": str(detected),
        "source": source,
        "evidence_sources": list(evidence_sources or ([source] if source else [])),
        "checked_at": time.time(),
        "explanation": explanation,
        "remediation": remediation,
        "repair_available": bool(repair_available),
        "privilege": privilege,
        "verification_scope": verification_scope,
        "confidence": confidence,
    }


def parse_systemd_dropin(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.is_file():
        return values
    try:
        for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
            line = raw.strip()
            if not line or line.startswith(("#", ";", "[")) or "=" not in line:
                continue
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()
    except OSError:
        return {}
    return values


def hardening_values_ok(values: dict[str, str]) -> tuple[bool, list[str]]:
    missing: list[str] = []
    for key, expected in HARDENING_REQUIRED.items():
        actual = str(values.get(key, "")).strip()
        if key == "RestrictAddressFamilies":
            if set(actual.split()) != set(expected.split()):
                missing.append(f"{key}={expected}")
        elif actual.lower() != expected.lower():
            missing.append(f"{key}={expected}")
    return not missing, missing


def user_service_hardening_posture() -> dict:
    services = {}
    for name, path in (
        ("lan-share", LAN_SHARE_HARDENING_DROPIN),
        ("wayvnc-remote", WAYVNC_HARDENING_DROPIN),
    ):
        values = parse_systemd_dropin(path)
        ok, missing = hardening_values_ok(values)
        services[name] = {
            "ok": ok,
            "path": str(path),
            "missing": missing,
            "directives": {key: values.get(key, "") for key in HARDENING_REQUIRED},
        }
    return {
        "ok": all(item["ok"] for item in services.values()),
        "security_revision": HARDENING_REVISION,
        "services": services,
    }


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def deployment_integrity_posture() -> dict:
    payload = load_json(DEPLOYMENT_MANIFEST, None)
    if not isinstance(payload, dict):
        return {
            "ok": False,
            "revision": "missing",
            "manifest": str(DEPLOYMENT_MANIFEST),
            "files": [],
            "reason": "Deployment integrity manifest is missing.",
        }

    items = payload.get("files")
    if not isinstance(items, list) or not items:
        return {
            "ok": False,
            "revision": str(payload.get("revision") or "unknown"),
            "manifest": str(DEPLOYMENT_MANIFEST),
            "files": [],
            "reason": "Deployment integrity manifest has no file inventory.",
        }

    results = []
    for item in items:
        if not isinstance(item, dict):
            continue
        raw_path = str(item.get("path") or "")
        expected = str(item.get("sha256") or "")
        expected_mode = str(item.get("mode") or "")
        path = Path(raw_path).expanduser()
        exists = path.is_file()
        actual = ""
        mode = ""
        error = ""
        if exists:
            try:
                actual = sha256_file(path)
                mode = f"{stat.S_IMODE(path.stat().st_mode):04o}"
            except OSError as exc:
                error = str(exc)
        hash_ok = bool(exists and expected and actual == expected)
        mode_ok = not expected_mode or mode == expected_mode
        results.append({
            "path": str(path),
            "exists": exists,
            "hash_ok": hash_ok,
            "mode_ok": mode_ok,
            "expected_sha256": expected,
            "actual_sha256": actual,
            "expected_mode": expected_mode,
            "actual_mode": mode,
            "error": error,
        })

    ok = bool(results) and all(row["hash_ok"] and row["mode_ok"] for row in results)
    return {
        "ok": ok,
        "revision": str(payload.get("revision") or "unknown"),
        "generated_at": payload.get("generated_at", ""),
        "manifest": str(DEPLOYMENT_MANIFEST),
        "files": results,
        "reason": "All package-owned files match the deployment manifest." if ok else "One or more package-owned files drifted from the deployment manifest.",
    }


def security_audit(services: dict, tailscale: dict, exposure: dict, slow: dict, wayvnc_security: dict) -> list[dict]:
    ssh = slow["ssh"]
    checks = [
        check("sshd-active", "SSH", "critical", "pass" if services["sshd"]["running"] else "fail",
              "SSH recovery service is running", "active", services["sshd"]["active_state"],
              "systemd", "SSH is the primary recovery path.", "Inspect sshd before changing authentication.",
              privilege="root", evidence_sources=["systemd"]),
        check("tailscale-active", "Tailscale", "critical", "pass" if tailscale["connected"] else "fail",
              "Tailscale is connected", "Running", tailscale["backend_state"], "tailscale status --json",
              "The tailnet provides private remote reachability.", "Inspect tailscaled and authentication state.",
              privilege="root", evidence_sources=["systemd", "tailscale status --json"]),
    ]

    configured = ssh.get("configured", {})
    configured_ok = (
        configured.get("permit_root_login", "").lower() == "no"
        and configured.get("password_authentication", "").lower() == "no"
        and configured.get("pubkey_authentication", "").lower() == "yes"
        and configured.get("kbd_interactive_authentication", "").lower() == "no"
        and configured.get("allow_users", "").split() == [USER]
    )
    checks.append(check(
        "ssh-configured-policy", "SSH", "warning", "pass" if configured_ok else "warn",
        "SSH hardening is configured", "root off · password off · pubkey on · intended user only",
        "matches configured policy" if configured_ok else "configured values differ",
        str(SSH_DROPIN), "This proves the configuration file intent, not the running daemon's effective state.",
        "Review the hardened SSH drop-in before making changes.", confidence="configured",
        evidence_sources=[str(SSH_DROPIN)]
    ))

    if ssh["effective_verified"]:
        effective = ssh.get("effective", {})
        rules = [
            ("root-off", "Root login disabled", effective.get("permit_root_login", "unknown"), "no", "critical"),
            ("password-off", "Password authentication disabled", effective.get("password_authentication", "unknown"), "no", "critical"),
            ("pubkey-on", "Public-key authentication enabled", effective.get("pubkey_authentication", "unknown"), "yes", "critical"),
            ("kbd-off", "Keyboard-interactive authentication disabled", effective.get("kbd_interactive_authentication", "unknown"), "no", "warning"),
        ]
        for check_id, title, detected, expected, severity in rules:
            checks.append(check(check_id, "SSH", severity, "pass" if detected.lower() == expected else "fail",
                                title, expected, detected, ssh["source"],
                                "Verified against the daemon's effective configuration.",
                                "Review the effective sshd policy before changing authentication.", privilege="root",
                                confidence="verified", evidence_sources=["sshd -T", str(SSH_DROPIN)]))
        allow_users = effective.get("allow_users", "").split()
        checks.append(check("allow-user", "SSH", "critical", "pass" if allow_users == [USER] else "fail",
                            "SSH is restricted to the intended account", USER, effective.get("allow_users", "") or "not declared",
                            ssh["source"], "AllowUsers is verified from sshd -T.", "Review AllowUsers before editing SSH.",
                            privilege="root", evidence_sources=["sshd -T"]))
        checks.append(check("ssh-effective-proof", "SSH", "info", "pass",
                            "Effective SSH configuration independently verified", "sshd -T verified", ssh["source"],
                            ssh["source"], "Configured and effective SSH state are independently distinguished.",
                            "No action required.", confidence="verified", evidence_sources=["sshd -T"]))
    else:
        checks.append(check("ssh-effective-proof", "SSH", "warning", "unknown",
                            "Effective SSH configuration needs verification", "effective sshd -T output",
                            ssh.get("effective_error") or "not verified", ssh["source"],
                            "Configured hardening looks correct, but this local claim is important enough to require effective daemon evidence.",
                            "Use Verify SSH. The app performs a targeted sshd -T check and may request Polkit authorization.",
                            repair_available=True, privilege="root", confidence="unverified", evidence_sources=[str(SSH_DROPIN)]))

    funnel_status = "fail" if tailscale["funnel"]["is_public"] else "pass" if tailscale["funnel"]["verification"] in {"tailnet-only", "off"} else "unknown"
    checks.append(check("funnel-off", "Exposure", "critical", funnel_status,
                        "Tailscale Funnel is not public", "off / tailnet-only", tailscale["funnel"]["verification"],
                        tailscale["funnel"]["source"], "Serve is tailnet-private; Funnel is internet-public.",
                        "Disable Funnel if public exposure is not intentional.", evidence_sources=["tailscale funnel status"]))

    serve = tailscale["serve"]
    serve_verification = str(serve.get("verification") or "unknown")
    if not serve.get("configured"):
        serve_status = "pass"
    elif serve_verification == "tailnet-only" and serve.get("tailnet_only") is True:
        serve_status = "pass"
    elif serve_verification == "public" or serve.get("is_public"):
        serve_status = "fail"
    else:
        serve_status = "unknown"
    checks.append(check(
        "serve-private-proof", "Exposure", "critical", serve_status,
        "Tailscale Serve privacy is positively classified", "off / tailnet-only", serve_verification,
        serve.get("source", "tailscale serve status"),
        "A configured route is not automatically private; the tailnet-only marker must be observed.",
        "Keep private actions blocked until Serve is explicitly verified tailnet-only.",
        confidence="verified" if serve_status == "pass" else "unverified",
        evidence_sources=["tailscale serve status"],
    ))

    unexpected = exposure["groups"]["unexpected"]
    checks.append(check("application-exposure", "Exposure", "critical", "fail" if unexpected else "pass",
                        "Known remote services follow their local bind policy", "no unexpected LAN Share / WayVNC exposure",
                        ", ".join(item["endpoint"] for item in unexpected) if unexpected else "expected binds",
                        "ss listener policy model", "Local listeners and application-level exposure can be verified from this machine.",
                        "Stop the affected service and repair its bind policy.", evidence_sources=["ss", "Tailscale Serve/Funnel state"]))

    checks.append(check("router-nat", "External exposure", "info", "external-unverified",
                        "Router/NAT exposure", "external reachability test", "outside local verification scope",
                        "local machine only", "The control center does not claim that router/NAT forwarding is absent without external evidence.",
                        "Use an external probe or router integration if that assurance is required.",
                        verification_scope="external", confidence="externally-unverified", evidence_sources=[]))

    checks.extend([
        check("share-demand", "Services", "warning", "pass" if not services["lan_share"]["boot_enabled"] else "warn",
              "LAN Share remains on-demand", "disabled", services["lan_share"]["enabled_state"], "systemd user unit state",
              "LAN Share is intentionally not a boot service.", "Disable boot enablement if it was enabled unintentionally.",
              repair_available=True, privilege="user", evidence_sources=["systemd --user"]),
        check("vnc-demand", "Services", "warning", "pass" if not services["wayvnc"]["boot_enabled"] else "warn",
              "WayVNC remains on-demand", "disabled", services["wayvnc"]["enabled_state"], "systemd user unit state",
              "Remote desktop is intentionally not a boot service.", "Disable boot enablement if it was enabled unintentionally.",
              repair_available=True, privilege="user", evidence_sources=["systemd --user"]),
        check("vnc-auth", "Remote desktop", "critical", "pass" if wayvnc_security.get("ok") else "fail",
              "WayVNC requires independent encrypted authentication",
              "VeNCrypt/TLS + dedicated password + dynamic Tailscale bind",
              wayvnc_security.get("reason", "unverified"),
              str(WAYVNC_CONFIG),
              "Tailnet binding is transport isolation; WayVNC authentication is a separate authorization layer.",
              "Repair the Arch Remote WayVNC security profile before starting remote desktop.",
              evidence_sources=[str(WAYVNC_CONFIG), str(WAYVNC_LAUNCHER), str(WAYVNC_SECURITY_DROPIN)]),
        check("linger", "Services", "warning", "pass" if slow["linger"]["enabled"] else "warn",
              "User linger is enabled", "yes", slow["linger"]["value"], slow["linger"]["source"],
              "Linger keeps user services manageable outside an interactive login.",
              "Enable linger intentionally if remote user services require it.", privilege="root", evidence_sources=["loginctl"]),
    ])

    hardening = user_service_hardening_posture()
    for service_name in ("lan-share", "wayvnc-remote"):
        service_hardening = hardening["services"][service_name]
        checks.append(check(
            f"{service_name}-sandbox", "Services", "warning",
            "pass" if service_hardening["ok"] else "warn",
            f"{service_name} runs with the Arch Remote sandbox profile",
            HARDENING_REVISION,
            "verified" if service_hardening["ok"] else "; ".join(service_hardening["missing"]) or "missing",
            service_hardening["path"],
            "The service remains able to use its intended user files/network while unnecessary kernel and privilege surfaces are restricted.",
            "Restore the package-owned hardening drop-in before using the service.",
            evidence_sources=[service_hardening["path"]],
        ))

    integrity = deployment_integrity_posture()
    checks.append(check(
        "deployment-integrity", "Integrity", "warning", "pass" if integrity["ok"] else "warn",
        "Arch Remote package-owned files match the installed manifest",
        "all managed hashes and modes match",
        integrity["reason"],
        str(DEPLOYMENT_MANIFEST),
        "This detects accidental source/config drift after the reviewed deployment.",
        "Re-run the reviewed installer or perform a new audit before accepting changed files.",
        evidence_sources=[str(DEPLOYMENT_MANIFEST)],
    ))
    return checks


def health_summary(checks: list[dict], tailscale: dict) -> dict:
    critical = [item for item in checks if item["status"] == "fail" and item["severity"] == "critical"]
    warnings = [item for item in checks if item["status"] in {"warn", "fail"} and item["severity"] != "critical"]
    local_unverified = [item for item in checks if item["verification_scope"] == "local" and item["status"] in {"unknown", "untested"}]
    external_unverified = [item for item in checks if item["verification_scope"] == "external" and item["status"] == "external-unverified"]
    if tailscale.get("health_messages"):
        warnings.append({"id": "tailscale-health"})

    verified_count = sum(item["status"] == "pass" for item in checks)
    if critical:
        status = "critical"
        label = "Critical"
        summary = f"{len(critical)} critical issue" + ("s" if len(critical) != 1 else "")
    elif warnings:
        status = "degraded"
        label = "Degraded"
        summary = f"{len(warnings)} warning" + ("s" if len(warnings) != 1 else "") + " · 0 critical"
    elif local_unverified:
        status = "operational"
        label = "Operational"
        summary = f"{verified_count} verified · {len(local_unverified)} local unverified · 0 issues"
    elif external_unverified:
        status = "healthy-locally"
        label = "Healthy locally"
        summary = "External exposure not tested"
    else:
        status = "healthy"
        label = "Healthy"
        summary = f"{verified_count} verified · 0 issues"

    return {
        "status": status,
        "label": label,
        "title": label,
        "summary": summary,
        "critical_count": len(critical),
        "warning_count": len(warnings),
        "verified_count": verified_count,
        "passed_count": verified_count,
        "local_unverified_count": len(local_unverified),
        "external_unverified_count": len(external_unverified),
        "unverified_count": len(local_unverified) + len(external_unverified),
        "check_count": len(checks),
        "issue_count": len(critical) + len(warnings),
    }


def listeners_owned_by_service(listeners: list[dict], main_pid: int, process_names: set[str]) -> tuple[bool, str]:
    """Verify expected user-service listeners belong to the systemd MainPID."""
    if not listeners:
        return False, "expected listener is absent"
    if not main_pid:
        return False, "systemd MainPID is unavailable"
    for item in listeners:
        listener_pid = int(item.get("pid") or 0)
        process = str(item.get("process") or "")
        if listener_pid != int(main_pid):
            return False, f"listener PID {listener_pid or 'unknown'} does not match systemd MainPID {main_pid}"
        if process_names and process not in process_names:
            return False, f"listener process {process or 'unknown'} is not an expected service process"
    return True, "listener process identity matches systemd MainPID"


def service_domain(services: dict, tailscale: dict, exposure: dict, graphical: dict, ssh_state_value: dict, wayvnc_security: dict | None = None) -> dict:
    by_port: dict[int, list[dict]] = {}
    for listener in exposure["listeners"]:
        by_port.setdefault(int(listener["port"]), []).append(listener)
    wayvnc_security = wayvnc_security or {"ok": True, "auth_mode": "test fixture", "username": "test"}

    def finish(service: dict, ready: bool, reachable: bool, reason: str, evidence_sources: list[str]):
        result = dict(service)
        result["ready"] = bool(ready)
        result["reachable"] = bool(reachable)
        result["healthy"] = bool(ready) if result["running"] else result["expected_state"] == "on-demand"
        result["readiness"] = "ready" if ready else "running-not-ready" if result["running"] else "expected-off" if result["expected_state"] == "on-demand" else "down"
        result["readiness_reason"] = reason
        result["evidence_sources"] = evidence_sources
        result["health"] = "ready" if ready else "degraded" if result["running"] and not ready else "expected-inactive" if result["expected_state"] == "on-demand" else "degraded"
        return result

    ssh = dict(services["sshd"])
    ssh["listeners"] = by_port.get(22, [])
    ssh["bind"] = ", ".join(item["endpoint"] for item in ssh["listeners"]) or "none"
    ssh_ready = bool(ssh["running"] and ssh["listeners"] and ssh_state_value.get("effective_verified") and ssh_state_value.get("secure"))
    if not ssh["running"]:
        ssh_reason = "sshd is not running"
    elif not ssh["listeners"]:
        ssh_reason = "sshd is running but no port 22 listener was detected"
    elif not ssh_state_value.get("effective_verified"):
        ssh_reason = "running; effective SSH policy not independently verified"
    elif not ssh_state_value.get("secure"):
        ssh_reason = "running; effective SSH policy does not match the hardened expectation"
    else:
        ssh_reason = "port 22 listening; effective key-only policy verified"
    ssh = finish(ssh, ssh_ready, bool(ssh["running"] and ssh["listeners"]), ssh_reason, ["systemd", "ss", "sshd -T"])
    ssh["reachability"] = "listener-detected" if ssh["reachable"] else "not-detected"

    tailscaled = dict(services["tailscaled"])
    ts_ready = bool(tailscaled["running"] and tailscale["connected"])
    ts_reason = "daemon active and tailnet connected" if ts_ready else "daemon running but tailnet is not connected" if tailscaled["running"] else "tailscaled is not running"
    tailscaled = finish(tailscaled, ts_ready, tailscale["connected"], ts_reason, ["systemd", "tailscale status --json"])
    tailscaled["reachability"] = "tailnet-connected" if tailscale["connected"] else "disconnected"

    share = dict(services["lan_share"])
    share["listeners"] = by_port.get(8000, [])
    share["bind"] = ", ".join(item["endpoint"] for item in share["listeners"]) or "none"
    listener_ok = bool(share["listeners"] and all(item["bind_scope"] == "loopback" for item in share["listeners"]))
    owner_ok, owner_reason = listeners_owned_by_service(
        share["listeners"], int(share.get("pid") or 0), {"python3", "python", "lan-share"}
    )
    share_ready = bool(share["running"] and listener_ok and owner_ok)
    share_reachable = bool(
        share_ready
        and private_exposure_verified(tailscale["serve"], tailscale["funnel"])
        and tailscale["serve"]["upstream_reachable"]
    )
    if not share["running"]:
        share_reason = "intentionally off"
    elif not listener_ok:
        share_reason = "running but expected 127.0.0.1:8000 listener is missing or unsafe"
    elif not owner_ok:
        share_reason = "loopback listener exists but process ownership is unverified — " + owner_reason
    else:
        share_reason = "127.0.0.1:8000 and listener process identity verified"
    share = finish(share, share_ready, share_reachable, share_reason, ["systemd --user", "ss process/PID", "Tailscale Serve/Funnel"])
    share["reachability"] = "private-serve" if share_reachable else "local-ready-route-offline" if share_ready else "not-ready"

    wayvnc = dict(services["wayvnc"])
    wayvnc["listeners"] = by_port.get(5900, [])
    wayvnc["bind"] = ", ".join(item["endpoint"] for item in wayvnc["listeners"]) or "none"
    wayvnc["graphical_ready"] = bool(graphical["hyprland_available"] and graphical["wayland_display"])
    listener_ok = bool(wayvnc["listeners"] and all(item["bind_scope"] == "tailnet" for item in wayvnc["listeners"]))
    owner_ok, owner_reason = listeners_owned_by_service(
        wayvnc["listeners"], int(wayvnc.get("pid") or 0), {"wayvnc"}
    )
    transport_ready = bool(
        wayvnc["running"] and wayvnc["graphical_ready"] and listener_ok and owner_ok and tailscale["connected"]
    )
    auth_ready = bool(wayvnc_security.get("ok"))
    wayvnc_ready = bool(transport_ready and auth_ready)
    wayvnc["transport_ready"] = transport_ready
    wayvnc["auth_ready"] = auth_ready
    wayvnc["auth_mode"] = str(wayvnc_security.get("auth_mode") or "unverified")
    wayvnc["auth_username"] = str(wayvnc_security.get("username") or "")
    wayvnc["auth_summary"] = "TLS + password verified" if auth_ready else "Authentication policy unverified"
    wayvnc["tailnet_acl_verification"] = str(wayvnc_security.get("tailnet_acl_verification") or "external-unverified")
    if not wayvnc["running"]:
        wayvnc_reason = "intentionally off; TLS/password authentication profile verified" if auth_ready else "intentionally off; authentication profile needs repair"
    elif not wayvnc["graphical_ready"]:
        wayvnc_reason = "running but no active Wayland/Hyprland session is available"
    elif not listener_ok:
        wayvnc_reason = "running but expected Tailscale-only :5900 listener is missing"
    elif not owner_ok:
        wayvnc_reason = "Tailscale-only listener exists but process ownership is unverified — " + owner_reason
    elif not tailscale["connected"]:
        wayvnc_reason = "listener exists but Tailscale is disconnected"
    elif not auth_ready:
        wayvnc_reason = "private transport is verified but independent WayVNC authentication is not"
    else:
        wayvnc_reason = "Wayland, process-owned Tailscale :5900, and WayVNC TLS/password authentication verified"
    wayvnc = finish(
        wayvnc, wayvnc_ready, transport_ready, wayvnc_reason,
        ["systemd --user", "Hyprland/Wayland", "ss process/PID", "Tailscale", "WayVNC TLS auth config"],
    )
    wayvnc["reachability"] = "tailnet-authenticated" if wayvnc_ready else "tailnet-transport" if transport_ready else "not-ready"

    return {"sshd": ssh, "tailscaled": tailscaled, "lan_share": share, "wayvnc": wayvnc}


def phone_guide(state: dict, slow: dict) -> dict:
    tailscale = state["tailscale"]
    services = state["services"]
    host = tailscale["dns_name"] or tailscale["hostname"] or state["host"]["hostname"]
    phone = tailscale.get("phone") or {}
    phone_addresses = set(phone.get("addresses") or [])
    auth = slow.get("ssh_auth") or {}
    ssh_observed = bool(auth.get("last_success_ip") and auth.get("last_success_ip") in phone_addresses)

    ssh_config = (
        "Host arch-pc\n"
        f"    HostName {host}\n"
        f"    User {USER}\n"
        "    IdentityFile ~/.ssh/id_ed25519\n"
        "    IdentitiesOnly yes\n"
        "    ServerAliveInterval 30\n"
        "    ServerAliveCountMax 3"
    )
    commands = "ssh arch-pc\narchctl status\narchctl shell"

    raw_share_url = tailscale["serve"]["url"]
    private_verified = private_exposure_verified(tailscale["serve"], tailscale["funnel"])
    safe_share_url = safe_private_share_url(raw_share_url, private_verified)
    pairing = private_share_pairing_readiness(state)

    if phone:
        tail_state = "connected" if phone.get("online") else "offline"
    else:
        tail_state = "not-detected"

    if ssh_observed:
        ssh_state_label, ssh_confidence = "observed", "observed"
    elif slow["ssh"].get("authorized_keys_exists") and services["sshd"].get("ready"):
        ssh_state_label, ssh_confidence = "configured", "configured-not-tested"
    else:
        ssh_state_label, ssh_confidence = "unavailable", "unverified"

    sftp_available = bool(services["sshd"].get("ready"))
    if services["wayvnc"].get("ready"):
        avnc_state = "ready"
    elif services["wayvnc"].get("running"):
        avnc_state = "degraded"
    elif not services["wayvnc"].get("graphical_ready"):
        avnc_state = "unavailable"
    else:
        avnc_state = "off"

    share_available = bool(services["lan_share"].get("reachable") and safe_share_url)

    return {
        "host": host,
        "user": USER,
        "ssh_command": "ssh arch-pc",
        "ssh_config": ssh_config,
        "commands": commands,
        "fingerprint": slow["ssh_host_fingerprint"],
        "device": phone,
        "readiness": {
            "tailscale": {"state": tail_state, "confidence": "observed" if phone else "unverified"},
            "ssh": {"state": ssh_state_label, "confidence": ssh_confidence, "last_observed_at": auth.get("last_success_at", 0)},
            "sftp": {"state": "available" if sftp_available else "unavailable", "confidence": "inferred-from-ssh" if sftp_available else "unverified"},
            "avnc": {"state": avnc_state, "confidence": "verified" if services["wayvnc"].get("ready") else "configured"},
            "share": {"state": "available" if share_available else "unavailable", "confidence": "verified" if share_available else "configured"},
        },
        "sftp": {
            "host": host, "port": 22, "user": USER, "root_path": str(HOME),
            "fingerprint": slow["ssh_host_fingerprint"]["fingerprint"],
        },
        "vnc": {
            "endpoint": f"{host}:5900" if host else "",
            "service_active": services["wayvnc"]["running"],
            "running": services["wayvnc"]["running"],
            "ready": services["wayvnc"].get("ready", False),
            "transport_ready": services["wayvnc"].get("transport_ready", False),
            "auth_ready": services["wayvnc"].get("auth_ready", False),
            "auth_mode": services["wayvnc"].get("auth_mode", "unverified"),
            "auth_username": services["wayvnc"].get("auth_username", ""),
            "state": avnc_state,
            "readiness_reason": services["wayvnc"].get("readiness_reason", ""),
            "start_available": bool(services["wayvnc"]["graphical_ready"] and tailscale["connected"] and services["wayvnc"].get("auth_ready")),
            "unavailable_reason": "" if services["wayvnc"]["graphical_ready"] and tailscale["connected"] and services["wayvnc"].get("auth_ready") else "No active Wayland session" if not services["wayvnc"]["graphical_ready"] else "Tailscale is disconnected" if not tailscale["connected"] else "WayVNC authentication profile needs repair",
        },
        "share": {
            "url": safe_share_url,
            "service_active": services["lan_share"]["running"],
            "running": services["lan_share"]["running"],
            "ready": services["lan_share"].get("ready", False),
            "configured": tailscale["serve"]["configured"],
            "upstream_reachable": tailscale["serve"]["upstream_reachable"],
            "is_private": private_verified,
            "tailnet_only": private_verified,
            "privacy_verification": "verified-private" if private_verified else "unverified",
            "pairing_available": pairing["available"],
            "pairing_reason": pairing["reason"],
            "pairing_checks": pairing["checks"],
            "pairing_cancel_supported": pair_command_support()["cancel_supported"],
        },
    }


def _activity_state_unlocked(current: dict) -> list[dict]:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    existing = load_json(ACTIVITY_FILE, {"previous": {}, "events": []})
    previous = existing.get("previous", {})
    events = list(existing.get("events", []))
    now = time.time()

    def add(kind: str, title: str, detail: str, severity="info"):
        events.insert(0, {"id": f"{int(now * 1000)}-{kind}-{len(events)}", "timestamp": now,
                          "kind": kind, "title": title, "detail": detail, "severity": severity})

    auth = current.get("ssh_auth") or {}
    compact = {
        "lan_share": bool(current["services"]["lan_share"]["running"]),
        "lan_share_ready": bool(current["services"]["lan_share"].get("ready")),
        "wayvnc": bool(current["services"]["wayvnc"]["running"]),
        "wayvnc_ready": bool(current["services"]["wayvnc"].get("ready")),
        "tailscale": bool(current["tailscale"]["connected"]),
        "serve": bool(current["tailscale"]["serve"]["configured"]),
        "serve_health": current["tailscale"]["serve"]["health"],
        "serve_url": current["tailscale"]["serve"]["url"],
        "funnel": current["tailscale"]["funnel"]["verification"],
        "health": current["health"]["status"],
        "ts_health": list(current["tailscale"].get("health_messages", [])),
        "devices": sorted(device["hostname"] for device in current["tailscale"]["devices"] if device["online"] and not device["is_self"]),
        "unexpected": sorted(item["endpoint"] for item in current["exposure"]["groups"]["unexpected"]),
        "ssh_success": float(auth.get("last_success_at", 0) or 0),
        "ssh_success_ip": str(auth.get("last_success_ip") or ""),
        "ssh_failures": int(auth.get("failure_count", 0) or 0),
        "lid": current["lid"].get("status"),
        "wifi_wake": current["wake"]["wifi"].get("configured"),
    }

    if previous:
        for key, label in (("lan_share", "LAN Share"), ("wayvnc", "Remote desktop"), ("tailscale", "Tailscale")):
            if previous.get(key) != compact[key]:
                add("service", f"{label} {'started' if compact[key] else 'stopped'}", "Observed from the canonical runtime snapshot.", "success" if compact[key] else "info")
        for key, label in (("lan_share_ready", "LAN Share"), ("wayvnc_ready", "Remote desktop")):
            if previous.get(key) != compact[key] and compact[key]:
                add("verification", f"{label} readiness verified", "Runtime and expected listener evidence now agree.", "success")
        if previous.get("serve") != compact["serve"] or previous.get("serve_health") != compact["serve_health"] or previous.get("serve_url") != compact["serve_url"]:
            add("serve", "Tailscale Serve state changed", f"{compact['serve_url'] or 'No URL'} · {compact['serve_health']}", "warning" if compact["serve_health"] == "degraded" else "info")
        if previous.get("funnel") != compact["funnel"]:
            add("exposure", "Funnel exposure state changed", compact["funnel"], "critical" if compact["funnel"] == "public" else "info")
        old_devices, new_devices = set(previous.get("devices", [])), set(compact["devices"])
        for name in sorted(new_devices - old_devices):
            add("device", f"{name} became online", "Tailnet peer is online.", "success")
        for name in sorted(old_devices - new_devices):
            add("device", f"{name} went offline", "Tailnet peer is offline.", "info")
        if previous.get("health") != compact["health"]:
            add("audit", f"Remote-access health changed to {current['health']['label']}", current["health"]["summary"], "warning" if compact["health"] in {"degraded", "critical"} else "success")
        old_unexpected, new_unexpected = set(previous.get("unexpected", [])), set(compact["unexpected"])
        for endpoint in sorted(new_unexpected - old_unexpected):
            add("exposure", "Unexpected listener exposure detected", endpoint, "critical")
        if previous.get("ts_health") != compact["ts_health"]:
            if compact["ts_health"]:
                add("tailscale", "Tailscale health warning appeared", "; ".join(compact["ts_health"]), "warning")
            elif previous.get("ts_health"):
                add("tailscale", "Tailscale health warning recovered", "Current Tailscale health is clear.", "success")
        if compact["ssh_success"] and compact["ssh_success"] != previous.get("ssh_success"):
            phone = current["tailscale"].get("phone") or {}
            phone_ips = set(phone.get("addresses") or [])
            if compact["ssh_success_ip"] in phone_ips:
                title = f"SSH key login from {phone.get('hostname') or 'phone'}"
            else:
                title = "SSH key login observed"
            add("auth", title, compact["ssh_success_ip"] or "Source address unavailable", "success")
        if compact["ssh_failures"] > int(previous.get("ssh_failures", 0) or 0):
            delta = compact["ssh_failures"] - int(previous.get("ssh_failures", 0) or 0)
            add("auth", "SSH authentication failures observed", f"{delta} new failure(s) in the bounded 24-hour evidence window.", "warning")
        if previous.get("lid") != compact["lid"]:
            add("configuration", "Lid policy state changed", str(compact["lid"]), "info")
        if previous.get("wifi_wake") != compact["wifi_wake"]:
            add("configuration", "WoWLAN configuration changed", str(compact["wifi_wake"]), "info")
    elif not events:
        add("system", "Arch Remote monitoring initialized", "Canonical runtime state store created.", "info")

    payload = {"previous": compact, "events": events[:ACTIVITY_LIMIT]}
    atomic_json(ACTIVITY_FILE, payload)
    return payload["events"]


def activity_state(current: dict) -> list[dict]:
    with advisory_lock(STATE_DATA_LOCK) as acquired:
        if not acquired:
            return []
        return _activity_state_unlocked(current)


def cached_snapshot() -> dict:
    state = load_json(RUNTIME_FILE, None)
    if not isinstance(state, dict):
        return {"error": True, "ok": False, "state": "cache-missing", "message": "No persisted Arch Remote state is available yet."}
    if int(state.get("schema_version", 0) or 0) != STATE_SCHEMA_VERSION:
        return {"error": True, "ok": False, "state": "cache-schema-mismatch", "message": "Persisted state schema is incompatible."}
    if str(state.get("ui_contract") or "") != UI_CONTRACT:
        return {"error": True, "ok": False, "state": "cache-contract-mismatch", "message": "Persisted UI contract is incompatible."}
    out = dict(state)
    generated = float(out.get("generated_at", 0) or 0)
    out["cache"] = {
        "source": "persisted",
        "age_seconds": max(0.0, time.time() - generated) if generated else None,
        "current_backend_revision": BACKEND_REVISION,
        "cached_backend_revision": str(out.get("backend_revision") or ""),
    }
    return out


def snapshot(force_slow=False) -> dict:
    checked = time.time()
    generation = next_generation()
    raw_services = services_state()
    tailscale = tailscale_state()
    listeners = listeners_state(tailscale)
    exposure = exposure_state(listeners, tailscale)
    graphical = graphical_state()
    host = host_state()
    slow = slow_state(force=force_slow)
    wayvnc_security = wayvnc_security_posture()
    hardening = user_service_hardening_posture()
    deployment_integrity = deployment_integrity_posture()
    audit = security_audit(raw_services, tailscale, exposure, slow, wayvnc_security)
    health = health_summary(audit, tailscale)
    services = service_domain(raw_services, tailscale, exposure, graphical, slow["ssh"], wayvnc_security)

    state = {
        "schema_version": STATE_SCHEMA_VERSION,
        "ui_contract": UI_CONTRACT,
        "backend_revision": BACKEND_REVISION,
        "generation": generation,
        "generated_at": checked,
        "fast_checked_at": checked,
        "slow_checked_at": slow["checked_at"],
        "health": health,
        "profile": "Remote desktop" if services["wayvnc"]["ready"] else "File sharing" if services["lan_share"]["reachable"] else "Secure idle" if services["sshd"]["running"] and tailscale["connected"] else "Custom",
        "host": host,
        "services": services,
        "tailscale": tailscale,
        "listeners": listeners,
        "exposure": exposure,
        "security_checks": audit,
        "ssh": slow["ssh"],
        "ssh_auth": slow.get("ssh_auth", {}),
        "ssh_host_fingerprint": slow["ssh_host_fingerprint"],
        "interfaces": slow["interfaces"],
        "wake": slow["wake"],
        "linger": slow["linger"],
        "lid": slow["lid"],
        "graphical": graphical,
        "wayvnc_security": wayvnc_security,
        "hardening": hardening,
        "deployment_integrity": deployment_integrity,
    }
    state["phone_guide"] = phone_guide(state, slow)
    state["activity"] = activity_state(state)
    state["cache"] = {"source": "live", "age_seconds": 0.0, "current_backend_revision": BACKEND_REVISION,
                      "cached_backend_revision": BACKEND_REVISION}
    atomic_json(RUNTIME_FILE, state)
    return state


def _pid_alive(pid: int) -> bool:
    try:
        if int(pid) <= 0:
            return False
        os.kill(int(pid), 0)
        return True
    except (OSError, ValueError, TypeError):
        return False


def _idle_operation() -> dict:
    return {
        "id": "", "active": False, "status": "idle", "phase": "idle",
        "label": "", "kind": "", "args": [], "service": "", "action": "",
        "source": "", "pid": 0, "started_at": 0.0, "updated_at": 0.0,
        "finished_at": 0.0, "message": "", "result_state": "",
        "backend_revision": BACKEND_REVISION,
    }


def _operation_read_unlocked() -> dict:
    payload = load_json(OPERATION_FILE, _idle_operation())
    if not isinstance(payload, dict):
        return _idle_operation()
    out = _idle_operation()
    out.update(payload)
    return out


def _operation_write_unlocked(payload: dict) -> dict:
    ensure_private_dir(OP_RUNTIME_DIR)
    normalized = _idle_operation()
    normalized.update(payload)
    normalized["backend_revision"] = BACKEND_REVISION
    atomic_json(OPERATION_FILE, normalized)
    try:
        OPERATION_FILE.chmod(0o600)
    except OSError:
        pass
    return normalized


def operation_status(operation_id: str = "") -> dict:
    with advisory_lock(OPERATION_META_LOCK) as acquired:
        if not acquired:
            return {"error": True, "ok": False, "message": "Operation metadata is busy."}
        operation = _operation_read_unlocked()
        if operation.get("active") and int(operation.get("pid") or 0) > 0 and not _pid_alive(int(operation.get("pid") or 0)):
            operation.update({
                "active": False,
                "status": "failed",
                "phase": "failed",
                "finished_at": time.time(),
                "updated_at": time.time(),
                "message": "The operation worker exited before publishing a final result.",
                "result_state": "worker-exited",
            })
            operation = _operation_write_unlocked(operation)
        if operation_id and operation.get("id") != operation_id:
            return {"error": True, "ok": False, "state": "operation-replaced", "message": "Requested operation is no longer the current operation.", "operation": operation}
        return {"ok": True, "operation": operation}


def _operation_spec(kind: str, args: list[str]) -> dict:
    if kind == "service" and len(args) == 2:
        name, action = args
        if name not in USER_SERVICES or action not in {"start", "stop", "restart"}:
            raise ValueError("Unsupported user-service operation.")
        label_name = "Private Share" if name == "lan-share" else "Remote Desktop"
        verb = {"start": "Starting", "stop": "Stopping", "restart": "Restarting"}[action]
        return {"label": f"{verb} {label_name}", "service": name, "action": action}
    if kind == "system-service" and len(args) == 2:
        name, action = args
        if name != "tailscaled" or action not in {"start", "restart"}:
            raise ValueError("Unsupported system-service operation.")
        return {"label": "Starting Tailscale" if action == "start" else "Restarting Tailscale", "service": name, "action": action}
    if kind == "lockdown" and not args:
        return {"label": "Locking interactive sharing", "service": "", "action": "lockdown"}
    if kind == "verify-ssh-effective" and not args:
        return {"label": "Verifying effective SSH policy", "service": "sshd", "action": "verify"}
    raise ValueError("Unsupported persistent operation.")


def _operation_dispatch(kind: str, args: list[str]) -> dict:
    if kind == "service":
        return service_action(args[0], args[1])
    if kind == "system-service":
        return system_service_action(args[0], args[1])
    if kind == "lockdown":
        return lockdown()
    if kind == "verify-ssh-effective":
        return verify_ssh_effective()
    raise ValueError("Unsupported operation worker command.")


def _action_lock_busy_payload() -> dict:
    current = operation_status().get("operation", {})
    label = str(current.get("label") or "another Arch Remote action")
    return {"error": True, "ok": False, "state": "busy", "message": f"Busy: {label} is already in progress.", "operation": current}


def locked_direct_call(callback) -> dict:
    with advisory_lock(ACTION_LOCK_FILE, blocking=False) as acquired:
        if not acquired:
            return _action_lock_busy_payload()
        return callback()


def operation_start(kind: str, args: list[str], source="controller") -> dict:
    spec = _operation_spec(kind, args)
    ensure_private_dir(OP_RUNTIME_DIR)
    with advisory_lock(OPERATION_META_LOCK) as acquired:
        if not acquired:
            return {"error": True, "ok": False, "state": "busy", "message": "Operation metadata is busy."}
        current = _operation_read_unlocked()
        if current.get("active"):
            pid = int(current.get("pid") or 0)
            if pid <= 0 or _pid_alive(pid):
                return {"error": True, "ok": False, "state": "busy", "message": f"Busy: {current.get('label') or 'another Arch Remote action'} is already in progress.", "operation": current}
            current.update({"active": False, "status": "failed", "phase": "failed", "finished_at": time.time(),
                            "updated_at": time.time(), "message": "Previous operation worker disappeared.", "result_state": "worker-exited"})
            _operation_write_unlocked(current)

        with advisory_lock(ACTION_LOCK_FILE, blocking=False) as lock_available:
            if not lock_available:
                return {"error": True, "ok": False, "state": "busy", "message": "Busy: another controller process owns the Arch Remote action lock."}

        op_id = uuid.uuid4().hex
        now = time.time()
        operation = _idle_operation()
        operation.update({
            "id": op_id, "active": True, "status": "queued", "phase": "queued",
            "label": spec["label"], "kind": kind, "args": list(args),
            "service": spec.get("service", ""), "action": spec.get("action", ""),
            "source": str(source), "started_at": now, "updated_at": now,
        })
        _operation_write_unlocked(operation)
        process = subprocess.Popen(
            [sys.executable, str(Path(__file__).resolve()), "operation-worker", op_id, kind, *args],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
            close_fds=True,
        )
        operation["pid"] = process.pid
        operation["updated_at"] = time.time()
        operation = _operation_write_unlocked(operation)
        return {"ok": True, "accepted": True, "message": spec["label"], "operation": operation}


def operation_worker(operation_id: str, kind: str, args: list[str]) -> int:
    with advisory_lock(ACTION_LOCK_FILE, blocking=False) as acquired:
        if not acquired:
            with advisory_lock(OPERATION_META_LOCK) as meta:
                if meta:
                    current = _operation_read_unlocked()
                    if current.get("id") == operation_id:
                        current.update({"active": False, "status": "failed", "phase": "failed", "finished_at": time.time(),
                                        "updated_at": time.time(), "message": "Another controller action acquired the global lock first.", "result_state": "busy"})
                        _operation_write_unlocked(current)
            return 2

        with advisory_lock(OPERATION_META_LOCK) as meta:
            if not meta:
                return 3
            current = _operation_read_unlocked()
            if current.get("id") != operation_id:
                return 4
            current.update({"status": "running", "phase": "running", "pid": os.getpid(), "updated_at": time.time()})
            _operation_write_unlocked(current)

        try:
            result = _operation_dispatch(kind, args)
        except Exception as error:
            result = {"error": True, "ok": False, "state": "failed", "message": str(error)}

        failed = bool(result.get("error") or result.get("ok") is False)
        message = str(result.get("message") or ("Operation failed" if failed else "Operation complete"))[:OPERATION_RESULT_MAX]
        result_state = str(result.get("state") or ("failed" if failed else "complete"))[:120]
        with advisory_lock(OPERATION_META_LOCK) as meta:
            if meta:
                current = _operation_read_unlocked()
                if current.get("id") == operation_id:
                    current.update({
                        "active": False,
                        "status": "failed" if failed else "succeeded",
                        "phase": "failed" if failed else "complete",
                        "updated_at": time.time(),
                        "finished_at": time.time(),
                        "message": message,
                        "result_state": result_state,
                    })
                    _operation_write_unlocked(current)
        return 1 if failed else 0


def operation_wait(operation_id: str, timeout=45.0) -> dict:
    deadline = time.time() + max(0.5, min(120.0, float(timeout)))
    latest = operation_status(operation_id)
    while time.time() < deadline:
        latest = operation_status(operation_id)
        operation = latest.get("operation") or {}
        if not operation.get("active"):
            return latest
        time.sleep(0.20)
    operation = (latest.get("operation") or {})
    return {"error": True, "ok": False, "state": "timeout", "message": "Timed out waiting for operation completion.", "operation": operation}


def wait_for_service(name: str, scope: str, running: bool, timeout=4.0) -> dict:
    deadline = time.time() + timeout
    latest = service_state(name, scope, expected_running=False)
    while time.time() < deadline:
        latest = service_state(name, scope, expected_running=False)
        if bool(latest["running"]) == bool(running):
            return latest
        time.sleep(0.25)
    return latest


def service_action(name: str, action: str) -> dict:
    if name not in USER_SERVICES:
        return {"error": True, "ok": False, "message": "Only LAN Share and WayVNC user services are controllable here."}
    if action not in {"start", "stop", "restart"}:
        return {"error": True, "ok": False, "message": "Unsupported service action."}

    label = "LAN Share" if name == "lan-share" else "WayVNC"
    stages = [{"phase": action + "ing", "status": "running", "detail": f"systemctl --user {action} {name}"}]
    if name == "lan-share" and action in {"stop", "restart"}:
        record_activity("pairing", "Private Share pairing cleared", "LAN Share stop/restart invalidates pending pairing credentials.", "info")
    try:
        current = snapshot(False)
        if action in {"start", "restart"} and name == "wayvnc-remote":
            if not current["graphical"]["hyprland_available"] or not current["graphical"]["wayland_display"]:
                raise ValueError("No active Wayland/Hyprland session was detected.")
            if not current["tailscale"]["connected"]:
                raise ValueError("Tailscale is disconnected.")
            vnc_security = current.get("wayvnc_security") or wayvnc_security_posture()
            if not vnc_security.get("ok"):
                raise ValueError("WayVNC security profile is not verified: " + str(vnc_security.get("reason") or "unknown"))

        systemctl = exe("systemctl")
        if not systemctl:
            raise ValueError("systemctl is unavailable.")
        result = run([systemctl, "--user", action, name], timeout=12.0)
        if result.returncode != 0:
            raise ValueError((result.stderr or result.stdout).strip() or f"{action} failed")

        expected_running = action in {"start", "restart"}
        stages.append({"phase": "runtime", "status": "checking", "detail": "Waiting for systemd runtime state"})
        verified = wait_for_service(name, "user", expected_running, timeout=4.5)
        if bool(verified["running"]) != expected_running:
            raise ValueError(f"systemctl returned success, but ActiveState={verified['active_state']}.")

        time.sleep(0.35)
        post = snapshot(False)
        key = "lan_share" if name == "lan-share" else "wayvnc"
        domain = post["services"][key]

        if expected_running:
            stages.append({"phase": "listener", "status": "checking", "detail": "Verifying expected listener and policy"})
            if not domain.get("ready"):
                record_activity("failure", f"{label} verification failed", domain.get("readiness_reason", "Not ready"), "warning")
                return {"error": True, "ok": False, "message": f"{label}: running but not ready — {domain.get('readiness_reason', 'verification failed')}",
                        "state": "running-not-ready", "service": domain, "stages": stages}
            stages.append({"phase": "ready", "status": "pass", "detail": domain.get("readiness_reason", "Ready")})
            record_activity("operator", f"{label} {action} verified", domain.get("readiness_reason", "Ready"), "success")
            return {"ok": True, "message": f"{label}: Ready", "state": "ready", "service": domain, "stages": stages}

        stages.append({"phase": "listener", "status": "checking", "detail": "Verifying listener removal"})
        if domain.get("listeners"):
            record_activity("failure", f"{label} stop verification failed", domain.get("bind", "listener still present"), "warning")
            return {"error": True, "ok": False, "message": f"{label}: service stopped but listener is still present", "state": "stopped-listener-present", "service": domain, "stages": stages}
        stages.append({"phase": "stopped", "status": "pass", "detail": "Service inactive and expected listener absent"})
        record_activity("operator", f"{label} stopped", "Service inactive; expected listener absent.", "info")
        return {"ok": True, "message": f"{label}: stopped and verified", "state": "stopped", "service": domain, "stages": stages}
    except Exception as error:
        record_activity("failure", f"{label} {action} failed", str(error), "warning")
        return {"error": True, "ok": False, "message": f"{label}: {error}", "state": "failed", "stages": stages}


def system_service_action(name: str, action: str) -> dict:
    if name != "tailscaled" or action not in {"start", "restart"}:
        return {"error": True, "ok": False, "message": "Only safe Tailscale start/restart is exposed here."}
    pkexec = exe("pkexec")
    systemctl = exe("systemctl")
    if not pkexec or not systemctl:
        return {"error": True, "ok": False, "message": "Polkit/systemctl is unavailable."}
    try:
        result = run([pkexec, systemctl, action, "tailscaled"], timeout=30.0)
        if result.returncode != 0:
            raise ValueError((result.stderr or result.stdout).strip() or f"tailscaled {action} failed")
        deadline = time.time() + 7.0
        last = None
        while time.time() < deadline:
            last = snapshot(False)
            if last["services"]["tailscaled"].get("ready"):
                record_activity("operator", f"Tailscale {action} verified", "Daemon active and tailnet connected.", "success")
                return {"ok": True, "message": "Tailscale: connected and verified", "state": "ready", "service": last["services"]["tailscaled"]}
            time.sleep(0.5)
        reason = (last or snapshot(False))["services"]["tailscaled"].get("readiness_reason", "Tailnet did not become ready")
        return {"error": True, "ok": False, "message": f"Tailscale: running but not ready — {reason}", "state": "running-not-ready"}
    except Exception as error:
        record_activity("failure", f"Tailscale {action} failed", str(error), "warning")
        return {"error": True, "ok": False, "message": f"Tailscale: {error}", "state": "failed"}


def lockdown() -> dict:
    before = snapshot(False)
    if before.get("services", {}).get("lan_share", {}).get("running"):
        record_activity("pairing", "Private Share pairing cleared", "Lock Sharing stops LAN Share and invalidates pending pairing credentials.", "info")
    if not before["services"]["sshd"]["running"] or not before["tailscale"]["connected"]:
        return {"error": True, "ok": False, "message": "Lockdown refused: SSH + Tailscale recovery is not currently available.", "state": "refused"}

    systemctl = exe("systemctl")
    if not systemctl:
        return {"error": True, "ok": False, "message": "systemctl is unavailable.", "state": "failed"}

    results = []
    failures = []
    for name, label, port in (("lan-share", "LAN Share", 8000), ("wayvnc-remote", "WayVNC", 5900)):
        current = service_state(name, "user", expected_running=False)
        if current["running"]:
            command = run([systemctl, "--user", "stop", name], timeout=12.0)
            if command.returncode != 0:
                failures.append(f"{label}: {(command.stderr or command.stdout).strip() or 'stop failed'}")
                results.append({"service": label, "status": "failed"})
                continue
        verified = wait_for_service(name, "user", False, timeout=4.5)
        post_listeners = [item for item in listeners_state(tailscale_state()) if item["port"] == port]
        if verified["running"] or post_listeners:
            failures.append(f"{label}: runtime/listener still present")
            results.append({"service": label, "status": "failed", "listeners": post_listeners})
        else:
            results.append({"service": label, "status": "stopped-verified"})

    post = snapshot(False)
    recovery_ok = bool(post["services"]["sshd"]["running"] and post["tailscale"]["connected"])
    if failures or not recovery_ok:
        detail = "; ".join(failures) if failures else "SSH/Tailscale recovery path changed unexpectedly"
        record_activity("lockdown", "Partial lockdown", detail, "warning")
        return {"error": True, "ok": False, "message": f"Partial lockdown — {detail}", "state": "partial-lockdown", "results": results, "recovery_ok": recovery_ok}

    record_activity("lockdown", "Sharing locked", "LAN Share and WayVNC stopped and listeners verified absent; SSH + Tailscale preserved.", "success")
    return {"ok": True, "message": "Sharing locked and independently verified", "state": "locked", "results": results, "recovery_ok": True}


def copy_text(value: str) -> dict:
    binary = exe("wl-copy")
    if not binary:
        raise ValueError("wl-copy is unavailable.")
    result = run([binary], timeout=4.0, input_text=value)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "Clipboard copy failed.")
    return {"ok": True, "message": "Copied to clipboard"}


def open_url(value: str) -> dict:
    parsed = urlparse(value)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise ValueError("Only HTTP(S) URLs can be opened.")
    binary = exe("xdg-open")
    if not binary:
        raise ValueError("xdg-open is unavailable.")
    subprocess.Popen([binary, value], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    return {"ok": True, "message": "Opened URL"}


def priority_name(value: str) -> str:
    try:
        number = int(value)
    except Exception:
        return "INFO"
    if number <= 3:
        return "ERROR"
    if number <= 4:
        return "WARN"
    if number in {5, 6}:
        return "INFO"
    return "DEBUG"


def logs(service_key: str, severity="all", window="1h", search="") -> dict:
    if service_key not in LOG_UNITS:
        raise ValueError("Unknown log source.")
    scope, unit = LOG_UNITS[service_key]
    journalctl = exe("journalctl")
    if not journalctl:
        raise ValueError("journalctl is unavailable.")
    since_map = {"15m": "15 minutes ago", "1h": "1 hour ago", "6h": "6 hours ago", "24h": "24 hours ago"}
    since = since_map.get(window, "1 hour ago")
    command = [journalctl]
    if scope == "user":
        command.append("--user")
    command += ["-u", unit, "--since", since, "-n", "240", "--no-pager", "-o", "json"]
    result = run(command, timeout=10.0)

    entries = []
    for raw_line in result.stdout.splitlines():
        try:
            item = json.loads(raw_line)
        except Exception:
            continue
        message = redact_pairing_secrets(str(item.get("MESSAGE") or ""))
        level = priority_name(str(item.get("PRIORITY") or "6"))
        try:
            timestamp = int(item.get("__REALTIME_TIMESTAMP") or 0) / 1_000_000.0
        except Exception:
            timestamp = 0.0
        if severity == "warning" and level not in {"WARN", "ERROR"}:
            continue
        if severity == "error" and level != "ERROR":
            continue
        if search and search.lower() not in message.lower():
            continue
        auth = service_key == "sshd" and any(term in message.lower() for term in ("accepted publickey", "authentication failure", "failed password", "invalid user", "failed publickey"))
        entries.append({"timestamp": timestamp, "level": "AUTH" if auth else level, "message": message, "identifier": str(item.get("SYSLOG_IDENTIFIER") or item.get("_COMM") or unit)})

    raw = "\n".join(f"{time.strftime('%H:%M:%S', time.localtime(item['timestamp']))} {item['level']:<5} {item['message']}" for item in entries)
    lower = raw.lower()
    known = []

    def issue(issue_id, severity_value, title, needle_count, detail, recovery, action="none"):
        if needle_count > 0:
            known.append({"id": issue_id, "severity": severity_value, "title": title, "count": needle_count,
                          "detail": detail, "recovery": recovery, "action": action})

    if service_key == "wayvnc":
        count = lower.count("failed to capture cursor")
        issue("wayvnc-cursor-capture", "warning", "WayVNC lost cursor capture", count,
              f"{count} occurrence(s) in {window}.", "Normal recovery: restart WayVNC.", "restart-wayvnc")
        bind_count = lower.count("address already in use") + lower.count("failed to bind")
        issue("wayvnc-bind", "warning", "WayVNC bind failure", bind_count,
              f"{bind_count} bind-related occurrence(s).", "Inspect port 5900 and restart after the conflict is resolved.")
    elif service_key == "sshd":
        auth_failures = sum(lower.count(term) for term in ("failed password", "authentication failure", "invalid user", "failed publickey"))
        issue("ssh-auth-failures", "warning" if auth_failures >= 3 else "info", "SSH authentication failures", auth_failures,
              f"{auth_failures} authentication failure(s) in {window}.", "Review source addresses and keep key-only authentication enabled.")
    elif service_key == "tailscaled":
        dns_count = lower.count("dns-forward-failing")
        if dns_count:
            recovered = "health(warnable=dns-forward-failing): ok" in lower
            known.append({"id": "tailscale-dns-forward", "severity": "info" if recovered else "warning",
                          "title": "Tailscale DNS forwarding warning", "count": dns_count,
                          "detail": f"{dns_count} health transition(s) in {window}.",
                          "recovery": "Recovered in-window" if recovered else "Check configured DNS and local connectivity.", "action": "none"})
        derp_count = lower.count("home derp changing") + lower.count("home is now derp")
        issue("tailscale-derp", "info", "Tailscale relay path changed", derp_count,
              f"{derp_count} DERP path transition(s).", "Informational unless persistent connectivity is degraded.")
        auth_count = lower.count("auth expired") + lower.count("authentication expired") + lower.count("needslogin")
        issue("tailscale-auth", "warning", "Tailscale authentication needs attention", auth_count,
              f"{auth_count} authentication-related occurrence(s).", "Re-authenticate Tailscale.")
    elif service_key == "lan-share":
        crash_count = lower.count("traceback")
        issue("lan-share-traceback", "warning", "LAN Share service crash", crash_count,
              f"{crash_count} Python traceback(s).", "Restart LAN Share and verify localhost:8000.", "restart-share")
        bind_count = lower.count("address already in use") + lower.count("failed to bind")
        issue("lan-share-bind", "warning", "LAN Share bind failure", bind_count,
              f"{bind_count} bind-related occurrence(s).", "Inspect localhost:8000 and restart after the conflict is resolved.")
        upstream_count = lower.count("connection refused") + lower.count("upstream")
        issue("lan-share-upstream", "info", "LAN Share upstream warning", upstream_count,
              f"{upstream_count} upstream-related occurrence(s).", "Verify the local share process and Tailscale Serve route.")

    return {
        "ok": True, "service": service_key, "severity": severity, "window": window, "search": search,
        "entries": entries, "raw": raw or "No matching log entries.", "text": raw or "No matching log entries.",
        "known_issues": [f"{item['title']} — {item['detail']} {item['recovery']}" for item in known],
        "known_issue_objects": known, "bounded": True, "entry_count": len(entries),
    }


def export_logs(service_key: str, severity="all", window="1h", search="") -> dict:
    payload = logs(service_key, severity, window, search)
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    path = EXPORT_DIR / f"{service_key}-{stamp}.log"
    path.write_text(payload["raw"] + "\n", encoding="utf-8")
    return {"ok": True, "message": f"Exported logs to {path}", "path": str(path)}


def record_event_command(kind: str, title: str, detail: str, severity="info") -> dict:
    record_activity(kind, title, detail, severity)
    return {"ok": True, "message": "Activity recorded"}


def selftest() -> dict:
    checks = []
    def assert_case(name, condition, detail):
        checks.append({"name": name, "passed": bool(condition), "detail": detail})

    service_base = {
        "name": "x", "loaded": True, "configured": True, "active": True, "running": True,
        "active_state": "active", "sub_state": "running", "enabled_state": "disabled", "enabled": False,
        "boot_enabled": False, "expected_running": False, "expected_state": "on-demand", "status": "running",
        "health": "healthy", "pid": 1, "restarts": 0, "started_at": "", "fragment_path": "",
        "memory": "—", "cpu_time": "—",
    }
    raw = {"sshd": dict(service_base, name="sshd", expected_running=True, expected_state="running"),
           "tailscaled": dict(service_base, name="tailscaled", expected_running=True, expected_state="running"),
           "lan_share": dict(service_base, name="lan-share"), "wayvnc": dict(service_base, name="wayvnc-remote")}
    tailscale = {
        "connected": True,
        "serve": {"configured": True, "upstream_reachable": True, "tailnet_only": True, "verification": "tailnet-only"},
        "funnel": {"is_public": False, "verification": "tailnet-only"},
    }
    graphical = {"hyprland_available": True, "wayland_display": "wayland-1"}
    ssh = {"effective_verified": True, "secure": True}
    exposure = {"listeners": [
        {"port": 22, "endpoint": "0.0.0.0:22", "bind_scope": "all-interfaces", "pid": 0, "process": ""},
        {"port": 8000, "endpoint": "127.0.0.1:8000", "bind_scope": "loopback", "pid": 1, "process": "python3"},
        {"port": 5900, "endpoint": "100.64.0.1:5900", "bind_scope": "tailnet", "pid": 1, "process": "wayvnc"},
    ]}
    good_vnc_security = {"ok": True, "auth_mode": "VeNCrypt/TLS + dedicated password", "username": "archremote", "tailnet_acl_verification": "external-unverified"}
    domain = service_domain(raw, tailscale, exposure, graphical, ssh, good_vnc_security)
    assert_case("LAN Share ready with loopback listener", domain["lan_share"]["ready"], domain["lan_share"]["readiness_reason"])
    assert_case("WayVNC ready with Wayland + tailnet listener + auth", domain["wayvnc"]["ready"], domain["wayvnc"]["readiness_reason"])
    no_vnc_auth = service_domain(raw, tailscale, exposure, graphical, ssh, {"ok": False, "auth_mode": "unverified"})
    assert_case("WayVNC private transport without independent auth is not ready", not no_vnc_auth["wayvnc"]["ready"] and no_vnc_auth["wayvnc"]["transport_ready"], no_vnc_auth["wayvnc"]["readiness_reason"])

    exposure_missing = {"listeners": [exposure["listeners"][0], exposure["listeners"][2]]}
    domain_missing = service_domain(raw, tailscale, exposure_missing, graphical, ssh)
    assert_case("Running LAN Share without :8000 is not ready", not domain_missing["lan_share"]["ready"] and domain_missing["lan_share"]["readiness"] == "running-not-ready", domain_missing["lan_share"]["readiness_reason"])

    no_wayland = service_domain(raw, tailscale, exposure, {"hyprland_available": False, "wayland_display": ""}, ssh)
    assert_case("WayVNC without Wayland is not ready", not no_wayland["wayvnc"]["ready"], no_wayland["wayvnc"]["readiness_reason"])

    ts_down = dict(tailscale, connected=False)
    ts_domain = service_domain(raw, ts_down, exposure, graphical, ssh)
    assert_case("Running tailscaled without connection is not ready", not ts_domain["tailscaled"]["ready"], ts_domain["tailscaled"]["readiness_reason"])

    ssh_unverified = service_domain(raw, tailscale, exposure, graphical, {"effective_verified": False, "secure": False})
    assert_case("Running sshd without effective proof is not ready", not ssh_unverified["sshd"]["ready"], ssh_unverified["sshd"]["readiness_reason"])

    health = health_summary([
        check("external", "Exposure", "info", "external-unverified", "External", "tested", "not tested", "local", "", "", verification_scope="external", confidence="externally-unverified")
    ], {"health_messages": []})
    assert_case("External-only uncertainty yields healthy-locally", health["status"] == "healthy-locally", health)

    safe = safe_private_share_url("https://host.tail000.ts.net/", True)
    unsafe = safe_private_share_url("https://user:secret@host.tail000.ts.net/?token=x", True)
    unknown_private = safe_private_share_url("https://host.tail000.ts.net/", False)
    assert_case("Permanent share URL accepts positively verified tailnet URL", bool(safe), safe)
    assert_case("Permanent share URL rejects credentials/query", not unsafe, unsafe)
    assert_case("Permanent share URL fails closed without private proof", not unknown_private, unknown_private)
    assert_case(
        "Private exposure proof accepts explicit tailnet-only state",
        private_exposure_verified(tailscale["serve"], tailscale["funnel"]),
        tailscale,
    )
    unknown_exposure = {
        "serve": {"configured": True, "tailnet_only": False, "verification": "unknown"},
        "funnel": {"is_public": False, "verification": "unknown"},
    }
    assert_case(
        "Ambiguous Serve/Funnel state is not treated as private",
        not private_exposure_verified(unknown_exposure["serve"], unknown_exposure["funnel"]),
        unknown_exposure,
    )

    share_offline = dict(
        tailscale,
        serve={"configured": True, "upstream_reachable": False, "tailnet_only": True, "verification": "tailnet-only"},
        funnel={"is_public": False, "verification": "tailnet-only"},
    )
    share_domain = service_domain(raw, share_offline, exposure, graphical, ssh)
    assert_case("Configured Serve with offline upstream is not called reachable", share_domain["lan_share"]["ready"] and not share_domain["lan_share"]["reachable"], share_domain["lan_share"])

    public_qr = safe_private_share_url("https://host.tail000.ts.net/", False)
    assert_case("Permanent share URL is suppressed without verified-private exposure", not public_qr, public_qr)

    ownership_bad = {"listeners": [dict(exposure["listeners"][0]), dict(exposure["listeners"][1], pid=999), dict(exposure["listeners"][2])]}
    ownership_domain = service_domain(raw, tailscale, ownership_bad, graphical, ssh)
    assert_case(
        "LAN Share listener owned by another PID is not ready",
        not ownership_domain["lan_share"]["ready"],
        ownership_domain["lan_share"]["readiness_reason"],
    )

    sample_pair = "https://host.tail000.ts.net/pair#t=temporary-super-secret-token"
    valid_pair, valid_pair_error = validate_pair_url(sample_pair, "https://host.tail000.ts.net/")
    assert_case("Pair URL accepts same-host credential shape", valid_pair, valid_pair_error)
    wrong_host_pair, _ = validate_pair_url(sample_pair, "https://other.tail000.ts.net/")
    assert_case("Pair URL rejects wrong Serve host", not wrong_host_pair, "wrong host accepted")
    redacted = redact_pairing_secrets("pair_url=" + sample_pair + " token #t=temporary-super-secret-token")
    assert_case("Pairing secret redaction removes token", "temporary-super-secret-token" not in redacted, redacted)
    assert_case("Pairing secret redaction marks content", "REDACTED" in redacted, redacted)

    sample_security = {
        "ok": True, "security_revision": "2.1-phase1b1", "session_required": True,
        "query_token_auth": False, "pairing_requires_verified_private_serve": True,
        "pin_rate_limit": {"client_max_failures": 5},
        "protected_paths": [".ssh", ".config"],
    }
    security_ok = bool(
        sample_security.get("ok")
        and sample_security.get("security_revision") == "2.1-phase1b1"
        and sample_security.get("session_required") is True
        and sample_security.get("query_token_auth") is False
        and sample_security.get("pairing_requires_verified_private_serve") is True
        and int((sample_security.get("pin_rate_limit") or {}).get("client_max_failures") or 0) >= 3
        and ".ssh" in (sample_security.get("protected_paths") or [])
        and ".config" in (sample_security.get("protected_paths") or [])
    )
    assert_case("LAN Share Phase 1B.1 security contract predicate", security_ok, sample_security)

    malformed_health = health_summary([
        check("local-proof", "SSH", "warning", "unknown", "Local proof", "verified", "unavailable", "synthetic", "", "", verification_scope="local", confidence="unverified")
    ], {"health_messages": []})
    assert_case("Locally verifiable uncertainty is operational, not healthy", malformed_health["status"] == "operational", malformed_health)

    share_spec = _operation_spec("service", ["lan-share", "start"])
    assert_case("Operation spec canonicalizes Private Share start", share_spec["service"] == "lan-share" and share_spec["action"] == "start", share_spec)
    vnc_spec = _operation_spec("service", ["wayvnc-remote", "restart"])
    assert_case("Operation spec canonicalizes Remote Desktop restart", vnc_spec["service"] == "wayvnc-remote" and vnc_spec["action"] == "restart", vnc_spec)
    rejected = False
    try:
        _operation_spec("service", ["sshd", "stop"])
    except ValueError:
        rejected = True
    assert_case("Operation spec rejects unsafe SSH stop", rejected, "sshd stop must not be dispatchable")
    idle = _idle_operation()
    assert_case("Idle operation is globally inactive", idle["active"] is False and idle["status"] == "idle", idle)

    hardening_ok, hardening_missing = hardening_values_ok(dict(HARDENING_REQUIRED))
    assert_case("Final user-service hardening contract accepts the required profile", hardening_ok and not hardening_missing, hardening_missing)
    weakened = dict(HARDENING_REQUIRED)
    weakened["NoNewPrivileges"] = "no"
    weak_ok, weak_missing = hardening_values_ok(weakened)
    assert_case("Final user-service hardening contract rejects weakened privilege policy", not weak_ok and "NoNewPrivileges=yes" in weak_missing, weak_missing)

    return {"ok": all(item["passed"] for item in checks), "checks": checks, "scenario_count": len(checks)}


def validate_state() -> dict:
    state = snapshot(True)
    checks = []
    def add(name, passed, detail):
        checks.append({"name": name, "passed": bool(passed), "detail": detail})
    add("SSH active", state["services"]["sshd"]["running"], state["services"]["sshd"]["active_state"])
    add("SSH boot enabled", state["services"]["sshd"]["boot_enabled"], state["services"]["sshd"]["enabled_state"])
    add("SSH configured key-only", state["ssh"]["configured"].get("pubkey_authentication") == "yes" and state["ssh"]["configured"].get("password_authentication") == "no", state["ssh"]["configured"])
    add("SSH effective policy verified", state["ssh"]["effective_verified"], state["ssh"]["source"])
    add("Tailscale connected", state["tailscale"]["connected"], state["tailscale"]["backend_state"])
    add(
        "Private Serve/Funnel exposure positively verified",
        private_exposure_verified(state["tailscale"]["serve"], state["tailscale"]["funnel"]),
        {
            "serve": state["tailscale"]["serve"].get("verification"),
            "funnel": state["tailscale"]["funnel"].get("verification"),
        },
    )
    add("Wi-Fi WoWLAN detection", state["wake"]["wifi"]["capability"] != "unknown", state["wake"]["wifi"])
    add("Linger detected", state["linger"]["value"] != "unknown", state["linger"]["value"])
    add("No known service bind violations", state["exposure"]["unexpected_count"] == 0, state["exposure"]["groups"]["unexpected"])
    share_security = lan_share_security_posture()
    add(
        "LAN Share security contract",
        bool(share_security.get("ok")),
        share_security,
    )
    pair_support = pair_command_support()
    add(
        "LAN Share pairing command detected",
        pair_support["available"],
        {
            "status": pair_support["status"],
            "binary": pair_support["binary"],
            "source": pair_support["source"],
        },
    )
    if state["services"]["lan_share"]["running"]:
        add("LAN Share readiness", state["services"]["lan_share"]["ready"], state["services"]["lan_share"]["readiness_reason"])
    vnc_security = state.get("wayvnc_security") or wayvnc_security_posture()
    add("WayVNC security contract", bool(vnc_security.get("ok")), vnc_security)
    hardening = state.get("hardening") or user_service_hardening_posture()
    add("User service hardening contract", bool(hardening.get("ok")), hardening)
    integrity = state.get("deployment_integrity") or deployment_integrity_posture()
    add("Deployment integrity manifest", bool(integrity.get("ok")), integrity)
    if state["services"]["wayvnc"]["running"]:
        add("WayVNC readiness", state["services"]["wayvnc"]["ready"], state["services"]["wayvnc"]["readiness_reason"])
    tests = selftest()
    add("Non-disruptive degraded-state simulation", tests["ok"], tests)
    return {"ok": all(item["passed"] for item in checks), "checks": checks,
            "state_summary": {"health": state["health"], "serve": state["tailscale"]["serve"], "funnel": state["tailscale"]["funnel"], "wake": state["wake"], "lid": state["lid"], "generation": state["generation"]}}



def command_reference(
    entry_id: str,
    title: str,
    command: str,
    description: str,
    category: str,
    platform: str,
    importance: str = "normal",
    mutates_state: bool = False,
    requires_root: bool = False,
    advanced: bool = False,
    dependencies: list[str] | None = None,
    related_service: str = "",
    copyable: bool = True,
    tags: list[str] | None = None,
    current_state: str = "",
    action_args: list[str] | None = None,
    action_label: str = "",
) -> dict:
    return {
        "id": entry_id,
        "kind": "command",
        "title": title,
        "command": command,
        "description": description,
        "category": category,
        "platform": platform,
        "importance": importance,
        "mutates_state": bool(mutates_state),
        "requires_root": bool(requires_root),
        "advanced": bool(advanced),
        "dependencies": dependencies or [],
        "related_service": related_service,
        "copyable": bool(copyable),
        "tags": tags or [],
        "current_state": current_state,
        "action_args": action_args or [],
        "action_label": action_label,
    }


def info_reference(
    entry_id: str,
    title: str,
    value: str,
    description: str,
    category: str,
    kind: str = "info",
    platform: str = "arch",
    importance: str = "normal",
    advanced: bool = False,
    copyable: bool = False,
    tags: list[str] | None = None,
    current_state: str = "",
) -> dict:
    return {
        "id": entry_id,
        "kind": kind,
        "title": title,
        "value": value,
        "description": description,
        "category": category,
        "platform": platform,
        "importance": importance,
        "mutates_state": False,
        "requires_root": False,
        "advanced": bool(advanced),
        "dependencies": [],
        "related_service": "",
        "copyable": bool(copyable and value),
        "tags": tags or [],
        "current_state": current_state,
        "action_args": [],
        "action_label": "",
    }


def reference_model(state: dict) -> dict:
    """
    Structured, searchable operational reference.

    Security contract:
      - Never include private SSH key contents.
      - Never include Tailscale auth keys.
      - Never include pairing bearer URLs / QR credentials.
      - Never include browser/session credentials.
    """
    phone = state.get("phone_guide") or {}
    tailscale = state.get("tailscale") or {}
    services = state.get("services") or {}
    ssh = state.get("ssh") or {}
    wake = state.get("wake") or {}
    lid = state.get("lid") or {}

    host = str(phone.get("host") or tailscale.get("dns_name") or tailscale.get("hostname") or state.get("host", {}).get("hostname") or "")
    share_url = str((phone.get("share") or {}).get("url") or "")
    vnc_endpoint = str((phone.get("vnc") or {}).get("endpoint") or (f"{host}:5900" if host else ""))
    fingerprint = str((phone.get("sftp") or {}).get("fingerprint") or "")
    user = str(phone.get("user") or USER)
    root_path = str((phone.get("sftp") or {}).get("root_path") or HOME)

    wifi = wake.get("wifi") or {}
    ethernet = wake.get("ethernet") or {}
    wifi_phy = str(wifi.get("phy") or "")
    ethernet_if = str(ethernet.get("interface_name") or "")

    share_running = bool((services.get("lan_share") or {}).get("running"))
    share_ready = bool((services.get("lan_share") or {}).get("ready"))
    desktop_running = bool((services.get("wayvnc") or {}).get("running"))
    desktop_ready = bool((services.get("wayvnc") or {}).get("ready"))

    share_state = "Ready" if share_ready else "Running · not ready" if share_running else "Expected off"
    desktop_state = "Ready" if desktop_ready else "Running · not ready" if desktop_running else "Expected off"

    # State-aware commands shown in the global reference.
    share_action_command = "archctl share-off" if share_running else "archctl share-on"
    share_action_label = "Stop now" if share_running else "Start now"
    share_action_args = ["service", "lan-share", "stop" if share_running else "start"]

    desktop_action_command = "archctl desktop-off" if desktop_running else "archctl desktop-on"
    desktop_action_label = "Stop now" if desktop_running else "Start now"
    desktop_action_args = ["service", "wayvnc-remote", "stop" if desktop_running else "start"]

    ssh_config = str(phone.get("ssh_config") or "")
    voyager_value = (
        f"Protocol: SFTP\nHost: {host or 'Not detected'}\nPort: 22\n"
        f"User: {user}\nRoot: {root_path}\nAuthentication: Voyager's own SSH keypair"
    )
    vnc_auth = services.get("wayvnc") or {}
    avnc_value = (
        f"Host: {host or 'Not detected'}\nPort: 5900\n"
        f"Endpoint: {vnc_endpoint or 'Not detected'}\n"
        f"Authentication: {vnc_auth.get('auth_mode') or 'unverified'}\n"
        f"Username: {vnc_auth.get('auth_username') or 'not configured'}\n"
        "Password: retrieve locally from ~/.config/wayvnc/arch-remote.conf"
    )

    sections = []

    sections.append({
        "id": "phone-essential",
        "title": "Essential phone commands",
        "icon": "star",
        "description": "The small set of commands that covers most normal phone usage.",
        "entries": [
            command_reference("phone-status", "Remote status", "archctl status",
                              "Show overall Arch remote-access status.", "phone", "phone",
                              importance="essential", tags=["status", "phone"]),
            command_reference("phone-shell", "Persistent Arch shell", "archctl shell",
                              "Open or reattach the phone-friendly tmux session on Arch.",
                              "terminal", "phone", importance="essential",
                              dependencies=["Termux", "SSH"], tags=["terminal", "tmux", "shell"]),
            command_reference("phone-share-on", "Private Share control", share_action_command,
                              "Start or stop the Private Share service from the phone.",
                              "private-share", "phone", importance="essential",
                              mutates_state=True, related_service="lan-share",
                              current_state=share_state, action_args=share_action_args,
                              action_label=share_action_label, tags=["share", "files", "qr"]),
            command_reference("phone-share-restart", "Recover Private Share", "archctl share-restart",
                              "Restart LAN Share when Private Share becomes unhealthy.",
                              "recovery", "phone", importance="recovery", mutates_state=True,
                              related_service="lan-share", tags=["share", "recovery"]),
            command_reference("phone-desktop-on", "Remote desktop", desktop_action_command,
                              "Start or stop WayVNC before opening AVNC.",
                              "remote-desktop", "phone", importance="essential",
                              mutates_state=True, related_service="wayvnc-remote",
                              current_state=desktop_state, action_args=desktop_action_args,
                              action_label=desktop_action_label, tags=["vnc", "avnc", "desktop"]),
            command_reference("phone-desktop-restart", "Recover Remote Desktop", "archctl desktop-restart",
                              "Restart WayVNC when AVNC or cursor capture stops working.",
                              "recovery", "phone", importance="recovery", mutates_state=True,
                              related_service="wayvnc-remote", tags=["vnc", "recovery"]),
        ],
    })

    sections.append({
        "id": "phone-terminal",
        "title": "Terminal & SSH",
        "icon": "terminal",
        "description": "Termux commands for direct and persistent shell access.",
        "entries": [
            command_reference("ssh-normal", "Normal SSH session", "ssh arch-pc",
                              "Open a normal SSH session from Termux.", "terminal", "phone",
                              tags=["ssh", "termux"]),
            command_reference("ssh-persistent", "Persistent phone shell", "archctl shell",
                              "Preferred persistent terminal. Reattaches the dedicated tmux session.",
                              "terminal", "phone", importance="essential",
                              dependencies=["Termux", "tmux"], tags=["ssh", "tmux"]),
            command_reference("ssh-underlying", "Underlying persistent-shell command",
                              "ssh -t arch-pc 'tmux -L phone new-session -A -s phone bash'",
                              "Direct equivalent of archctl shell.", "terminal", "phone",
                              advanced=True, tags=["ssh", "tmux", "advanced"]),
            command_reference("ssh-connectivity", "Quick connectivity check",
                              "ssh arch-pc 'echo connected'",
                              "Verify that SSH connectivity works without opening an interactive shell.",
                              "diagnostics", "phone", tags=["ssh", "test"]),
            command_reference("ssh-arch-status", "Direct Arch remote status",
                              "ssh arch-pc 'arch-remote status'",
                              "Run the Arch-side controller directly, bypassing archctl.",
                              "diagnostics", "phone", advanced=True, tags=["ssh", "status"]),
            command_reference("ssh-ts-status", "Inspect Tailscale remotely",
                              "ssh arch-pc 'tailscale status'",
                              "Inspect Tailscale on the Arch machine from Termux.",
                              "diagnostics", "phone", advanced=True, tags=["tailscale", "ssh"]),
            command_reference("ssh-add", "Unlock Termux SSH key", "ssh-add ~/.ssh/id_ed25519",
                              "Load the Termux private key into the current ssh-agent. Arch Remote never displays the key contents.",
                              "ssh", "phone", advanced=True, tags=["ssh", "key"]),
            command_reference("ssh-add-list", "Show loaded SSH keys", "ssh-add -l",
                              "List keys currently loaded in the Termux ssh-agent.",
                              "ssh", "phone", advanced=True, tags=["ssh", "key"]),
        ],
    })

    sections.append({
        "id": "files",
        "title": "Files",
        "icon": "folder",
        "description": "SFTP and Private Share workflows.",
        "entries": [
            command_reference("files-sftp", "Interactive SFTP", "archctl files",
                              "Open interactive SFTP from Termux. Equivalent to sftp arch-pc.",
                              "files", "phone", importance="essential",
                              dependencies=["Termux", "SSH"], tags=["sftp", "files"]),
            command_reference("files-sftp-direct", "Direct SFTP", "sftp arch-pc",
                              "Direct SFTP command using the arch-pc SSH alias.",
                              "files", "phone", tags=["sftp", "files"]),
            info_reference("voyager-client", "Voyager", voyager_value,
                           "Graphical SFTP file browser. Use Voyager's own SSH keypair; never copy the Termux private key into Voyager.",
                           "files", kind="client", platform="phone", copyable=False,
                           tags=["voyager", "sftp", "android"]),
            info_reference("share-workflow", "Private Share workflow",
                           "Arch Remote → Start Private Share → Generate one-time QR → Scan on phone",
                           "Normal quick-transfer workflow. The permanent Serve URL and temporary pairing credential are separate.",
                           "private-share", kind="workflow", platform="both",
                           importance="essential", tags=["share", "qr", "browser"]),
        ],
    })

    sections.append({
        "id": "private-share",
        "title": "Private Share",
        "icon": "folder_shared",
        "description": "Stable private route, one-scan access and advanced LAN Share administration.",
        "entries": [
            info_reference("share-url", "Permanent private URL", share_url,
                           "Stable Tailscale Serve URL for manual browser access. This is not an authentication credential.",
                           "private-share", kind="endpoint", platform="both",
                           copyable=bool(share_url), current_state=share_state,
                           tags=["serve", "url", "browser"]),
            info_reference("share-pairing", "One-scan access", "Generate QR from Arch Remote",
                           "The QR uses a short-lived single-use pairing credential. Pairing secrets are never stored in this reference layer.",
                           "private-share", kind="workflow", platform="both",
                           importance="essential", tags=["qr", "pairing"]),
            command_reference("share-status", "LAN Share status", "lan-share status",
                              "Check LAN Share process state.", "private-share", "arch",
                              advanced=True, tags=["share", "status"]),
            command_reference("share-pair", "Generate pairing from terminal", "lan-share pair",
                              "Advanced fallback for one-time pairing. Normal use should generate the QR inside Arch Remote.",
                              "private-share", "arch", advanced=True, mutates_state=True,
                              tags=["pairing", "qr"]),
            command_reference("share-pair-json", "Machine-readable pairing", "lan-share pair --json",
                              "Internal/advanced pairing generation used by Arch Remote. Output contains a temporary secret and must not be logged.",
                              "private-share", "arch", advanced=True, mutates_state=True,
                              tags=["pairing", "internal"]),
            command_reference("share-systemd-start", "Start LAN Share directly", "systemctl --user start lan-share",
                              "Direct systemd control.", "private-share", "arch",
                              advanced=True, mutates_state=True, related_service="lan-share"),
            command_reference("share-systemd-stop", "Stop LAN Share directly", "systemctl --user stop lan-share",
                              "Direct systemd control.", "private-share", "arch",
                              advanced=True, mutates_state=True, related_service="lan-share"),
            command_reference("share-systemd-restart", "Restart LAN Share directly", "systemctl --user restart lan-share",
                              "Direct systemd control.", "private-share", "arch",
                              advanced=True, mutates_state=True, related_service="lan-share"),
        ],
    })

    sections.append({
        "id": "remote-desktop",
        "title": "Remote Desktop",
        "icon": "desktop_windows",
        "description": "WayVNC / AVNC workflow, endpoint and recovery.",
        "entries": [
            info_reference("avnc-config", "AVNC connection", avnc_value,
                           "Android remote desktop client. WayVNC must be ready first.",
                           "remote-desktop", kind="endpoint", platform="phone",
                           copyable=bool(vnc_endpoint), current_state=desktop_state,
                           tags=["avnc", "vnc", "endpoint"]),
            command_reference("desktop-on", "Start Remote Desktop", "archctl desktop-on",
                              "Start WayVNC, then open AVNC.", "remote-desktop", "phone",
                              importance="essential", mutates_state=True, related_service="wayvnc-remote"),
            command_reference("desktop-off", "Stop Remote Desktop", "archctl desktop-off",
                              "Stop WayVNC.", "remote-desktop", "phone",
                              importance="essential", mutates_state=True, related_service="wayvnc-remote"),
            command_reference("desktop-restart", "Restart Remote Desktop", "archctl desktop-restart",
                              "Normal recovery when AVNC stops working or cursor capture fails.",
                              "recovery", "phone", importance="recovery", mutates_state=True,
                              related_service="wayvnc-remote"),
            command_reference("vnc-logs", "WayVNC logs", "archctl vnc-logs",
                              "Phone-side shortcut for recent WayVNC logs. Prefer the Arch Remote Logs page for normal use.",
                              "logs", "phone", importance="recovery", tags=["vnc", "logs"]),
            command_reference("vnc-systemd", "WayVNC status", "systemctl --user status wayvnc-remote",
                              "Direct Arch-side service status.", "remote-desktop", "arch",
                              advanced=True),
            command_reference("vnc-journal", "Recent WayVNC journal",
                              "journalctl --user -u wayvnc-remote -n 60 --no-pager",
                              "Advanced/recovery fallback. Normal log viewing stays inside Arch Remote.",
                              "logs", "arch", advanced=True, tags=["vnc", "journal"]),
        ],
    })

    sections.append({
        "id": "clients",
        "title": "Android clients",
        "icon": "apps",
        "description": "What application to use for each task.",
        "entries": [
            info_reference("client-termux", "Terminal → Termux", "Termux",
                           "SSH, persistent shell and archctl commands.", "clients",
                           kind="client", platform="phone", importance="essential"),
            info_reference("client-voyager", "Files → Voyager", "Voyager",
                           "Graphical SFTP browser rooted at your Arch home directory.", "clients",
                           kind="client", platform="phone", importance="essential"),
            info_reference("client-avnc", "Desktop → AVNC", "AVNC",
                           "Remote control of the current Hyprland/Wayland session.", "clients",
                           kind="client", platform="phone", importance="essential"),
            info_reference("client-tailscale", "Private network → Tailscale", "Tailscale",
                           "Private connectivity between the phone and Arch.", "clients",
                           kind="client", platform="phone", importance="essential"),
            info_reference("client-browser", "Quick transfer → Browser", "Browser via Private Share QR",
                           "Scan the one-time Private Share QR for authenticated browser access.", "clients",
                           kind="client", platform="phone", importance="essential"),
        ],
    })

    sections.append({
        "id": "tailscale",
        "title": "Tailscale",
        "icon": "vpn_lock",
        "description": "Private-network state and exposure checks.",
        "entries": [
            command_reference("ts-status", "Tailscale status", "tailscale status",
                              "Inspect tailnet connectivity and peers.", "tailscale", "arch"),
            command_reference("ts-ip", "Tailscale IPv4", "tailscale ip -4",
                              "Show this machine's current Tailscale IPv4 address.", "tailscale", "arch"),
            command_reference("ts-serve", "Serve status", "tailscale serve status",
                              "Inspect private tailnet HTTP(S) exposure. Private Share uses Serve.",
                              "tailscale", "arch", tags=["serve", "private"]),
            command_reference("ts-funnel", "Funnel status", "tailscale funnel status",
                              "Inspect public internet exposure. Funnel should normally remain off.",
                              "tailscale", "arch", tags=["funnel", "public"]),
            command_reference("share-security", "LAN Share security contract", "lan-share security --json",
                              "Inspect session, PIN-rate-limit and protected-path policy without starting the service.",
                              "security", "arch", tags=["share", "security", "policy"]),
        ],
    })

    sections.append({
        "id": "ssh-security",
        "title": "SSH & security",
        "icon": "key",
        "description": "Effective SSH policy, config location and recovery-safe diagnostics.",
        "entries": [
            info_reference("ssh-config-path", "SSH hardening config",
                           "/etc/ssh/sshd_config.d/99-remote.conf",
                           "Expected key-only remote-access policy.",
                           "configuration", kind="config", copyable=True,
                           tags=["ssh", "config"]),
            info_reference("ssh-policy", "Expected SSH policy",
                           "PermitRootLogin no\nPubkeyAuthentication yes\nPasswordAuthentication no\nKbdInteractiveAuthentication no\nAllowUsers " + user,
                           "Reference policy. Do not change authentication casually during recovery.",
                           "ssh", kind="policy", copyable=True, tags=["ssh", "security"]),
            command_reference("ssh-validate", "Validate SSH config", "sudo sshd -t",
                              "Validate SSH configuration syntax before restarting anything.",
                              "ssh", "arch", requires_root=True, advanced=True),
            command_reference("ssh-effective", "Show effective SSH config", "sudo sshd -T",
                              "Display the effective daemon configuration.", "ssh", "arch",
                              requires_root=True, advanced=True),
            command_reference("ssh-logs", "Recent SSH logs", "sudo journalctl -u sshd -n 60 --no-pager",
                              "Advanced recovery fallback. Prefer Arch Remote Logs for normal use.",
                              "logs", "arch", requires_root=True, advanced=True),
            info_reference("ssh-fingerprint", "Server fingerprint", fingerprint,
                           "Compare this public host fingerprint when configuring clients.",
                           "ssh", kind="fingerprint", platform="both",
                           copyable=bool(fingerprint), tags=["ssh", "fingerprint"]),
            info_reference("ssh-termux-config", "Generated Termux SSH config", ssh_config,
                           "Dynamic config using the currently detected Tailscale hostname.",
                           "ssh", kind="config", platform="phone", copyable=bool(ssh_config),
                           tags=["ssh", "termux", "config"]),
        ],
    })

    sections.append({
        "id": "network-diagnostics",
        "title": "Network diagnostics",
        "icon": "lan",
        "description": "Advanced listener checks and expected bind policy.",
        "entries": [
            command_reference("ss-all", "All TCP listeners", "ss -ltnp",
                              "Inspect all listening TCP sockets.", "diagnostics", "arch",
                              advanced=True),
            command_reference("ss-ssh", "SSH listener", "ss -ltnp | grep ':22'",
                              "Expected: 0.0.0.0:22 and/or [::]:22.", "diagnostics", "arch",
                              advanced=True),
            command_reference("ss-share", "LAN Share listener", "ss -ltnp | grep ':8000'",
                              "Expected while active: 127.0.0.1:8000.", "diagnostics", "arch",
                              advanced=True),
            command_reference("ss-vnc", "WayVNC listener", "ss -ltnp | grep ':5900'",
                              "Expected while active: current Tailscale IP on port 5900. Expected inactive: no :5900 listener.",
                              "diagnostics", "arch", advanced=True),
        ],
    })

    config_entries = [
        ("cfg-ssh", "SSH hardening", "/etc/ssh/sshd_config.d/99-remote.conf"),
        ("cfg-lid", "Lid policy", "/etc/systemd/logind.conf.d/90-remote-access.conf"),
        ("cfg-wowlan", "WoWLAN dispatcher", "/etc/NetworkManager/dispatcher.d/90-wowlan"),
        ("cfg-wayvnc-launcher", "WayVNC launcher", str(HOME / ".local/bin/wayvnc-remote")),
        ("cfg-wayvnc-service", "WayVNC user service", str(HOME / ".config/systemd/user/wayvnc-remote.service")),
        ("cfg-share-service", "LAN Share user service", str(HOME / ".config/systemd/user/lan-share.service")),
        ("cfg-share-app", "LAN Share application", str(HOME / ".local/share/lan-share/app.py")),
        ("cfg-controller", "Arch-side controller", str(HOME / ".local/bin/arch-remote")),
        ("cfg-phone-ssh", "Phone SSH config", "~/.ssh/config"),
        ("cfg-phone-key", "Phone private-key location", "~/.ssh/id_ed25519"),
        ("cfg-phone-archctl", "Phone archctl wrapper", "~/.local/bin/archctl"),
        ("cfg-phone-bashrc", "Phone shell config", "~/.bashrc"),
    ]
    sections.append({
        "id": "configuration",
        "title": "Configuration locations",
        "icon": "folder_open",
        "description": "Where the remote-access configuration lives. Private-key contents are never exposed.",
        "entries": [
            info_reference(entry_id, title, value,
                           "Configuration/reference location.", "configuration",
                           kind="config", platform="both" if "phone" in entry_id else "arch",
                           copyable=True, advanced=True, tags=["config", "path"])
            for entry_id, title, value in config_entries
        ],
    })

    power_entries = []
    if wifi_phy:
        power_entries.append(
            command_reference("wowlan-show", "Show WoWLAN state",
                              f"iw phy {wifi_phy} wowlan show",
                              "Show current Wi-Fi wake state using the detected PHY.",
                              "power", "arch", advanced=True, tags=["wifi", "wake"])
        )
    else:
        power_entries.append(
            info_reference("wowlan-missing", "WoWLAN command",
                           "Wi-Fi PHY not currently detected",
                           "Arch Remote generates the command dynamically when a PHY is available.",
                           "power", kind="status", advanced=True)
        )
    if ethernet_if:
        power_entries.append(
            command_reference("wol-show", "Show Ethernet WoL", f"sudo ethtool {ethernet_if}",
                              "Show Ethernet Wake-on-LAN capability and current state using the detected interface.",
                              "power", "arch", requires_root=True, advanced=True, tags=["ethernet", "wake"])
        )
    else:
        power_entries.append(
            info_reference("wol-missing", "Ethernet WoL command",
                           "Ethernet interface not currently detected",
                           "Arch Remote generates the command dynamically when an Ethernet interface is available.",
                           "power", kind="status", advanced=True)
        )
    power_entries.extend([
        command_reference("linger-show", "Show user linger",
                          f"loginctl show-user {user} -p Linger",
                          "Show whether the user service manager remains available outside an interactive login.",
                          "power", "arch", advanced=True),
        info_reference("lid-policy", "Intended lid policy",
                       "Battery → Hibernate\nExternal power → Ignore lid\nDocked → Ignore lid",
                       "Configured at /etc/systemd/logind.conf.d/90-remote-access.conf. A normal reboot may be required before the runtime behavior is verified.",
                       "power", kind="policy", advanced=False,
                       current_state=str(lid.get("status") or "unknown")),
    ])
    sections.append({
        "id": "power",
        "title": "Power & Wake",
        "icon": "power",
        "description": "Wake capability, linger and lid-policy reference.",
        "entries": power_entries,
    })

    sections.append({
        "id": "recovery",
        "title": "Recovery playbooks",
        "icon": "health_and_safety",
        "description": "Safe first-response sequences. Diagnose before weakening security.",
        "entries": [
            info_reference("recover-desktop", "Remote Desktop does not work",
                           "1. archctl desktop-restart\n2. archctl vnc-logs\n3. Verify Tailscale\n4. Verify Hyprland/Wayland session\n5. Open AVNC again",
                           "Do not change network exposure or authentication as a first response.",
                           "recovery", kind="recovery", platform="phone",
                           importance="recovery", copyable=True, tags=["vnc", "avnc"]),
            info_reference("recover-share", "Private Share does not work",
                           "1. archctl share-restart\n2. archctl share-logs\n3. Check the private Serve URL\n4. Generate a fresh one-time pairing QR",
                           "Keep Serve private and regenerate pairing rather than reusing an expired credential.",
                           "recovery", kind="recovery", platform="phone",
                           importance="recovery", copyable=True, tags=["share", "qr"]),
            info_reference("recover-ssh", "SSH does not work",
                           "1. Check the Tailscale app\n2. Try ssh arch-pc\n3. Locally check systemctl status sshd\n4. Inspect SSH logs",
                           "Diagnose connectivity and daemon state before changing SSH authentication.",
                           "recovery", kind="recovery", platform="both",
                           importance="recovery", copyable=True, tags=["ssh"]),
            info_reference("recover-tailscale", "Tailscale does not work",
                           "1. tailscale status\n2. systemctl status tailscaled\n3. Restart only if needed",
                           "Preserve SSH/local recovery while diagnosing the tailnet.",
                           "recovery", kind="recovery", platform="arch",
                           importance="recovery", copyable=True, tags=["tailscale"]),
            info_reference("recover-lock", "Lock Sharing",
                           "LAN Share OFF\nWayVNC OFF\nTailscale remains ON\nSSH recovery remains ON",
                           "Use the Arch Remote Lock Sharing action; no terminal command is required.",
                           "recovery", kind="recovery", platform="both",
                           importance="recovery", tags=["lockdown", "security"]),
        ],
    })

    # Complete archctl index, kept structured rather than duplicated throughout UI.
    sections.append({
        "id": "archctl",
        "title": "Complete archctl reference",
        "icon": "menu_book",
        "description": "Phone wrapper command index.",
        "entries": [
            command_reference("archctl-status", "Status", "archctl status", "Show remote-access status.", "archctl", "phone"),
            command_reference("archctl-shell", "Persistent shell", "archctl shell", "Open/reattach the phone tmux shell.", "archctl", "phone"),
            command_reference("archctl-files", "SFTP files", "archctl files", "Open interactive SFTP.", "archctl", "phone"),
            command_reference("archctl-share-on", "Start share", "archctl share-on", "Start LAN Share.", "archctl", "phone", mutates_state=True),
            command_reference("archctl-share-off", "Stop share", "archctl share-off", "Stop LAN Share.", "archctl", "phone", mutates_state=True),
            command_reference("archctl-share-restart", "Restart share", "archctl share-restart", "Restart LAN Share.", "archctl", "phone", mutates_state=True),
            command_reference("archctl-desktop-on", "Start desktop", "archctl desktop-on", "Start WayVNC.", "archctl", "phone", mutates_state=True),
            command_reference("archctl-desktop-off", "Stop desktop", "archctl desktop-off", "Stop WayVNC.", "archctl", "phone", mutates_state=True),
            command_reference("archctl-desktop-restart", "Restart desktop", "archctl desktop-restart", "Restart WayVNC.", "archctl", "phone", mutates_state=True),
            command_reference("archctl-vnc-logs", "VNC logs", "archctl vnc-logs", "Show WayVNC logs.", "archctl", "phone"),
            command_reference("archctl-share-logs", "Share logs", "archctl share-logs", "Show LAN Share logs.", "archctl", "phone"),
            command_reference("archctl-url", "Private Share URL", "archctl url", "Show the stable private Serve URL.", "archctl", "phone"),
        ],
    })

    # Defensive final secret scan. Reference entries may include stable endpoints,
    # but never a one-time pairing bearer URL.
    forbidden = (
        "/pair#t=",
        "authkey-",
        "session_cookie",
        "pair_url",
    )
    serialized = json.dumps(sections, ensure_ascii=False)
    if any(token in serialized for token in forbidden):
        raise ValueError("Reference model secret-safety check failed.")

    return {
        "ok": True,
        "schema_version": REFERENCE_SCHEMA_VERSION,
        "generated_at": time.time(),
        "snapshot_generation": int(state.get("generation", 0) or 0),
        "dynamic": {
            "tailscale_hostname": host,
            "tailscale_ip": str(tailscale.get("ipv4") or ""),
            "serve_url": share_url,
            "vnc_endpoint": vnc_endpoint,
            "ssh_fingerprint": fingerprint,
            "wifi_phy": wifi_phy,
            "ethernet_interface": ethernet_if,
            "user": user,
        },
        "sections": sections,
    }



def contract_payload() -> dict:
    return {
        "ok": True,
        "schema_version": STATE_SCHEMA_VERSION,
        "ui_contract": UI_CONTRACT,
        "backend_revision": BACKEND_REVISION,
        "reference_schema_version": REFERENCE_SCHEMA_VERSION,
        "operation_contract": 1,
        "hardening_revision": HARDENING_REVISION,
        "deployment_integrity_contract": 1,
    }


def main() -> int:
    if len(sys.argv) < 2:
        return emit({"error": True, "message": "missing command"})
    try:
        command = sys.argv[1]
        if command in {"--help", "help"}:
            return emit({
                "ok": True,
                "commands": [
                    "snapshot", "snapshot-cache", "contract", "operation-start", "operation-status", "operation-wait",
                    "service", "system-service", "wayvnc-security", "hardening", "integrity", "verify-ssh-effective", "pairing-create", "pairing-cancel",
                    "pairing-capability", "reference", "lockdown", "logs", "export-logs", "record-event", "selftest", "validate",
                ],
                **contract_payload(),
            })
        if command == "contract":
            return emit(contract_payload())
        if command == "wayvnc-security":
            return emit(wayvnc_security_posture())
        if command == "hardening":
            return emit(user_service_hardening_posture())
        if command == "integrity":
            return emit(deployment_integrity_posture())
        if command == "snapshot":
            return emit(snapshot("--full" in sys.argv[2:]))
        if command == "snapshot-cache":
            return emit(cached_snapshot())
        if command == "operation-start":
            return emit(operation_start(sys.argv[2], sys.argv[3:], source="cli" if os.environ.get("ARCH_REMOTE_CLI") == "1" else "ui"))
        if command == "operation-status":
            return emit(operation_status(sys.argv[2] if len(sys.argv) > 2 else ""))
        if command == "operation-wait":
            timeout = float(sys.argv[3]) if len(sys.argv) > 3 else 45.0
            return emit(operation_wait(sys.argv[2], timeout))
        if command == "operation-worker":
            return operation_worker(sys.argv[2], sys.argv[3], sys.argv[4:])
        if command == "service":
            return emit(locked_direct_call(lambda: service_action(sys.argv[2], sys.argv[3])))
        if command == "system-service":
            return emit(locked_direct_call(lambda: system_service_action(sys.argv[2], sys.argv[3])))
        if command == "verify-ssh-effective":
            return emit(locked_direct_call(verify_ssh_effective))
        if command == "pairing-create":
            return emit(locked_direct_call(pairing_create))
        if command == "pairing-cancel":
            return emit(locked_direct_call(pairing_cancel))
        if command == "reference":
            return emit(reference_model(snapshot(False)))
        if command == "pairing-capability":
            state = snapshot(False)
            readiness = private_share_pairing_readiness(state)
            support = pair_command_support()
            return emit({
                "ok": True,
                "available": readiness["available"],
                "reason": readiness["reason"],
                "checks": readiness["checks"],
                "executable_found": support["installed"],
                "pair_supported": support["available"],
                "pair_support_status": support["status"],
                "binary": support["binary"],
                "cancel_supported": support["cancel_supported"],
            })
        if command == "lockdown":
            return emit(locked_direct_call(lockdown))
        if command == "copy":
            return emit(copy_text(sys.argv[2]))
        if command == "open-url":
            return emit(open_url(sys.argv[2]))
        if command == "logs":
            if len(sys.argv) > 3 and sys.argv[3] == "--errors":
                return emit(logs(sys.argv[2], "warning", "1h", ""))
            severity = sys.argv[3] if len(sys.argv) > 3 else "all"
            window = sys.argv[4] if len(sys.argv) > 4 else "1h"
            search = sys.argv[5] if len(sys.argv) > 5 else ""
            return emit(logs(sys.argv[2], severity, window, search))
        if command == "export-logs":
            severity = sys.argv[3] if len(sys.argv) > 3 else "all"
            window = sys.argv[4] if len(sys.argv) > 4 else "1h"
            search = sys.argv[5] if len(sys.argv) > 5 else ""
            return emit(export_logs(sys.argv[2], severity, window, search))
        if command == "record-event":
            severity = sys.argv[5] if len(sys.argv) > 5 else "info"
            return emit(record_event_command(sys.argv[2], sys.argv[3], sys.argv[4], severity))
        if command == "selftest":
            return emit(selftest())
        if command == "validate":
            return emit(validate_state())
        raise ValueError(f"unknown command: {command}")
    except Exception as error:
        return emit({"error": True, "message": str(error)})



if __name__ == "__main__":
    raise SystemExit(main())
