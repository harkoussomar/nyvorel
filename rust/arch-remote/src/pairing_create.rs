//! One-shot pairing credential handling. The URL is never logged, passed in argv,
//! or persisted. Raw LAN Share output and QR bytes are explicitly cleared.
use base64::{engine::general_purpose::STANDARD, Engine as _};
use serde::Deserialize;
use serde_json::{json, Value};
use std::io::{self, Read, Write};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};
use url::Url;

struct Sensitive(Vec<u8>);
impl Drop for Sensitive {
    fn drop(&mut self) {
        if !self.0.is_empty() {
            // SAFETY: the Vec exclusively owns this initialized byte range.
            unsafe { libc::explicit_bzero(self.0.as_mut_ptr().cast(), self.0.len()) };
        }
    }
}

fn bounded(
    command: &mut Command,
    stdin: Option<&[u8]>,
    timeout: Duration,
) -> Option<(bool, Sensitive)> {
    command.stdout(Stdio::piped()).stderr(Stdio::null());
    command.stdin(if stdin.is_some() {
        Stdio::piped()
    } else {
        Stdio::null()
    });
    let mut child = command.spawn().ok()?;
    let output = child.stdout.take()?;
    let reader = thread::spawn(move || {
        let mut bytes = Vec::new();
        let _ = output.take(1_048_577).read_to_end(&mut bytes);
        Sensitive(bytes)
    });
    if let Some(bytes) = stdin {
        if child.stdin.take()?.write_all(bytes).is_err() {
            let _ = child.kill();
            let _ = child.wait();
            let _ = reader.join();
            return None;
        }
    }
    let deadline = Instant::now() + timeout;
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break Some(status),
            Ok(None) if Instant::now() < deadline => thread::sleep(Duration::from_millis(5)),
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                break None;
            }
        }
    };
    let bytes = reader.join().ok()?;
    if bytes.0.len() > 1_048_576 {
        return None;
    }
    Some((status?.success(), bytes))
}

pub(crate) fn revoke_command_succeeded(binary: &str) -> bool {
    bounded(
        Command::new(binary).args(["pair", "--cancel", "--json"]),
        None,
        Duration::from_secs(6),
    )
    .is_some_and(|(success, _output)| success)
}

#[derive(Deserialize)]
struct PairPayload<'a> {
    #[serde(borrow)]
    pair_url: Option<&'a str>,
    expires_at: Option<Value>,
    expires_in: Option<Value>,
    single_use: Option<bool>,
}

fn integer(value: Option<&Value>) -> Option<i64> {
    match value? {
        Value::Number(number) => number
            .as_i64()
            .or_else(|| number.as_f64().map(|n| n as i64)),
        Value::String(text) => text.parse().ok(),
        Value::Bool(value) => Some(i64::from(*value)),
        _ => None,
    }
}

fn valid_url(pair_url: &str, serve_url: &str) -> Result<(), &'static str> {
    let pair = Url::parse(pair_url).map_err(|_| "Pairing URL is not a valid URL.")?;
    let serve = Url::parse(serve_url).map_err(|_| "Pairing URL is not a valid URL.")?;
    if pair.scheme() != "https" || serve.scheme() != "https" {
        return Err("Pairing requires HTTPS.");
    }
    let pair_host = pair.host_str().unwrap_or("");
    if pair_host.is_empty() || pair_host != serve.host_str().unwrap_or("") {
        return Err("Pairing URL does not match the current private Serve host.");
    }
    if !pair_host.ends_with(".ts.net") {
        return Err("Pairing URL is not a Tailscale HTTPS address.");
    }
    if !pair.username().is_empty()
        || pair.password().is_some_and(|password| !password.is_empty())
        || pair.query().is_some_and(|query| !query.is_empty())
    {
        return Err("Pairing URL contains unexpected URL components.");
    }
    if pair.path().trim_end_matches('/') != "/pair" {
        return Err("Pairing URL path is unexpected.");
    }
    let fragment = pair.fragment().unwrap_or("");
    if !fragment.starts_with("t=") || fragment.len() <= 10 {
        return Err("Pairing URL is missing the one-time credential.");
    }
    Ok(())
}

fn fail(message: impl AsRef<str>) -> Value {
    json!({"error": true, "ok": false, "state": "error", "message": message.as_ref()})
}

pub fn derive(input: &Value) -> Value {
    let readiness = &input["readiness"];
    let checks_ok = readiness["checks"]
        .as_object()
        .is_some_and(|checks| !checks.is_empty() && checks.values().all(|item| item == true));
    if readiness["available"] != true || !checks_ok {
        return fail("Pairing readiness is not verified.");
    }
    let pair_binary = input["pair_binary"].as_str().unwrap_or("");
    let qrencode = input["qrencode"].as_str().unwrap_or("");
    let serve_url = input["serve_url"].as_str().unwrap_or("");
    if pair_binary.is_empty()
        || qrencode.is_empty()
        || serve_url.is_empty()
        || serve_url != readiness["serve_url"].as_str().unwrap_or("")
    {
        return fail("Pairing dependencies are unavailable.");
    }
    let Some((pair_success, raw)) = bounded(
        Command::new(pair_binary).args(["pair", "--json"]),
        None,
        Duration::from_secs(8),
    ) else {
        return fail("Pairing generation failed. LAN Share rejected the pairing request.");
    };
    if !pair_success {
        return fail("Pairing generation failed. LAN Share rejected the pairing request.");
    }
    let Ok(payload) = serde_json::from_slice::<PairPayload<'_>>(&raw.0) else {
        return fail(
            "Pairing generation failed. LAN Share returned invalid machine-readable state.",
        );
    };
    let pair_url = payload.pair_url.unwrap_or("");
    if pair_url.len() > 8192 {
        return fail("Pairing generation failed. Pairing URL is not a valid URL.");
    }
    if let Err(reason) = valid_url(pair_url, serve_url) {
        return fail(format!("Pairing generation failed. {reason}"));
    }
    let (Some(expires_at), Some(expires_in)) = (
        integer(payload.expires_at.as_ref()),
        integer(payload.expires_in.as_ref()),
    ) else {
        return fail("Pairing generation failed. Expiration metadata is invalid.");
    };
    if payload.single_use != Some(true) {
        return fail(
            "Pairing generation failed. LAN Share did not mark the credential single-use.",
        );
    }
    let now = input["now"].as_i64().unwrap_or(0);
    if expires_at <= now || expires_in <= 0 || expires_at > now + 900 || expires_in > 900 {
        return fail("Pairing generation failed. Credential lifetime is not short-lived.");
    }
    let Some((qr_success, png)) = bounded(
        Command::new(qrencode).args(["-o", "-", "-t", "PNG", "-s", "7", "-m", "2"]),
        Some(pair_url.as_bytes()),
        Duration::from_secs(5),
    ) else {
        return fail("Pairing QR rendering failed.");
    };
    if !qr_success || png.0.is_empty() {
        return fail("Pairing QR rendering failed.");
    }
    json!({"ok": true, "state": "ready", "message": "One-scan pairing QR ready",
        "expires_at": expires_at, "expires_in": expires_in, "single_use": true,
        "qr_data_url": format!("data:image/png;base64,{}", STANDARD.encode(&png.0)),
        "server_cancel_supported": input["cancel_supported"] == true})
}

pub fn run() -> Value {
    let mut input = Vec::new();
    if io::stdin().take(65_537).read_to_end(&mut input).is_err() || input.len() > 65_536 {
        return fail("Pairing input is too large.");
    }
    match serde_json::from_slice::<Value>(&input) {
        Ok(value) => derive(&value),
        Err(_) => fail("Invalid pairing input."),
    }
}
