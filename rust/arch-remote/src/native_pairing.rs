//! One-shot pairing with Rust readiness and activity handling.
use serde_json::{json, Value};

use crate::{
    activity, find_exe, native_snapshot, now, pair_support, pairing_cancel, pairing_create,
    pairing_readiness, runtime_dir, Flock,
};

fn fail(message: impl AsRef<str>) -> Value {
    json!({"error": true, "ok": false, "state": "error", "message": message.as_ref()})
}

pub fn create() -> Value {
    let Ok(_lock) = Flock::try_acquire(&runtime_dir().join("action.lock")) else {
        return fail("Another Arch Remote action is already in progress.");
    };
    let state = native_snapshot::run(false);
    if state.get("error") == Some(&Value::Bool(true)) {
        return fail("Could not verify pairing readiness.");
    }
    let binary = native_snapshot::lan_share_binary();
    let support = pair_support::run(&binary);
    let qrencode = find_exe("qrencode")
        .map(|path| path.to_string_lossy().into_owned())
        .unwrap_or_default();
    let readiness = pairing_readiness::derive(&json!({"state": state, "support": support,
        "qrencode_available": !qrencode.is_empty()}));
    if readiness["available"] != true {
        let reason = readiness["reason"].as_str().unwrap_or("not ready");
        return json!({"error": true, "ok": false, "state": "error",
            "message": format!("Cannot generate pairing QR — {reason}"), "reason": reason});
    }
    let result = pairing_create::derive(&json!({"readiness": readiness, "pair_binary": binary,
        "qrencode": qrencode, "serve_url": readiness["serve_url"], "now": now() as i64,
        "cancel_supported": support["cancel_supported"]}));
    if result["ok"] == true {
        let seconds = result["expires_in"].as_i64().unwrap_or(0);
        activity::record(
            "pairing",
            "Private Share pairing generated",
            &format!("Single-use credential created; expires in {seconds}s."),
            "info",
        );
    }
    result
}

pub fn cancel() -> Value {
    let Ok(_lock) = Flock::try_acquire(&runtime_dir().join("action.lock")) else {
        return fail("Another Arch Remote action is already in progress.");
    };
    let binary = native_snapshot::lan_share_binary();
    let support = pair_support::run(&binary);
    let result = pairing_cancel::derive(&json!({"binary": binary,
        "cancel_supported": support["cancel_supported"]}));
    if result["ok"] == true {
        if result["backend_revoked"] == true {
            activity::record(
                "pairing",
                "Private Share pairing cancelled",
                "Pending pairing credential revoked server-side.",
                "info",
            );
        } else {
            activity::record("pairing", "Private Share pairing dismissed",
                "QR hidden locally; backend token was not claimed revoked and will expire or be replaced.", "info");
        }
    }
    result
}

pub fn capability() -> Value {
    let state = native_snapshot::run(false);
    if state.get("error") == Some(&Value::Bool(true)) {
        return fail("Could not verify pairing readiness.");
    }
    let binary = native_snapshot::lan_share_binary();
    let support = pair_support::run(&binary);
    let readiness = pairing_readiness::derive(&json!({"state": state, "support": support,
        "qrencode_available": find_exe("qrencode").is_some()}));
    json!({"ok": true, "available": readiness["available"], "reason": readiness["reason"],
        "checks": readiness["checks"], "executable_found": support["installed"],
        "pair_supported": support["available"], "pair_support_status": support["status"],
        "binary": support["binary"], "cancel_supported": support["cancel_supported"]})
}
