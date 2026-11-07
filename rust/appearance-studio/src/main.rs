//! One-shot Appearance Studio backend. There is no resident process.
//!
//! All user-facing Appearance Studio commands are handled in Rust. Existing
//! system theme helpers remain external integration boundaries.

mod color_image;
mod engine;
mod intelligence;
mod kvantum;
mod material_scss;
mod modes;
mod palette;
mod request;
mod semantic_radius;
mod transaction;

use serde_json::{json, Map, Value};
use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::os::fd::AsRawFd;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{self, Command, Stdio};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const CATALOG: &str = include_str!("catalog.json");

#[link(name = "crypto")]
extern "C" {
    fn SHA256(data: *const u8, len: usize, digest: *mut u8) -> *mut u8;
}

fn sha256_hex(data: &[u8]) -> String {
    let mut digest = [0_u8; 32];
    // SAFETY: data and digest are live allocations of the stated sizes; SHA256
    // writes exactly 32 bytes to the caller-provided digest buffer.
    unsafe { SHA256(data.as_ptr(), data.len(), digest.as_mut_ptr()) };
    let mut result = String::with_capacity(64);
    for byte in digest {
        use std::fmt::Write as _;
        write!(&mut result, "{byte:02x}").expect("writing to String cannot fail");
    }
    result
}

fn xdg_path(variable: &str, fallback: &str) -> Result<PathBuf, String> {
    let home = env::var_os("HOME").ok_or("HOME is unset")?;
    let base = env::var_os(variable)
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| Path::new(&home).join(fallback));
    Ok(base)
}

fn config_path() -> Result<PathBuf, String> {
    Ok(xdg_path("XDG_CONFIG_HOME", ".config")?.join("nyvorel/config.json"))
}

fn state_path() -> Result<PathBuf, String> {
    Ok(xdg_path("XDG_CONFIG_HOME", ".config")?.join("nyvorel/appearance-studio.json"))
}

fn colors_path() -> Result<PathBuf, String> {
    Ok(xdg_path("XDG_STATE_HOME", ".local/state")?.join("quickshell/user/generated/colors.json"))
}

fn lock_path() -> Result<PathBuf, String> {
    Ok(xdg_path("XDG_CACHE_HOME", ".cache")?
        .join("nyvorel-appearance-studio/appearance-studio.lock"))
}

fn preview_path() -> Result<PathBuf, String> {
    Ok(xdg_path("XDG_CACHE_HOME", ".cache")?.join("nyvorel-appearance-studio/preview"))
}

fn preview_allowed_paths() -> Result<Vec<PathBuf>, String> {
    let config = xdg_path("XDG_CONFIG_HOME", ".config")?;
    let generated = xdg_path("XDG_STATE_HOME", ".local/state")?.join("quickshell/user/generated");
    let home = PathBuf::from(env::var_os("HOME").ok_or("HOME is unset")?);
    let mut paths = vec![
        generated.join("colors.json"),
        config.join("hypr/hyprland/colors.lua"),
        config.join("hypr/hyprlock/colors.conf"),
        config.join("fuzzel/fuzzel_theme.ini"),
        config.join("gtk-3.0/gtk.css"),
        config.join("gtk-4.0/gtk.css"),
    ];
    for editor in [
        "Code",
        "VSCodium",
        "Code - OSS",
        "Code - Insiders",
        "Cursor",
        "Antigravity",
    ] {
        paths.push(config.join(editor).join("User/settings.json"));
    }
    paths.extend([
        config.join("nyvorel/config.json"),
        generated.join("material_colors.scss"),
        generated.join("color.txt"),
        config.join("hypr/custom/appearance-runtime.lua"),
        config.join("kitty/kitty.conf"),
        home.join(".config/kitty/nyvorel-dynamic-theme.conf"),
        home.join(".config/starship.toml"),
        home.join(".config/kitty/tab_bar.py"),
        home.join(".config/fish/conf.d/99-nyvorel-dynamic-theme.fish"),
        home.join(".local/state/nyvorel/terminal-startup-overlay.fish"),
    ]);
    Ok(paths)
}

fn local_path(raw: &str) -> PathBuf {
    let decoded = if let Some(url) = raw.strip_prefix("file://") {
        let encoded_path = if url.starts_with('/') {
            url
        } else {
            url.find('/').map(|index| &url[index..]).unwrap_or("")
        };
        let bytes = encoded_path.as_bytes();
        let mut output = Vec::with_capacity(bytes.len());
        let mut index = 0;
        while index < bytes.len() {
            if bytes[index] == b'%' && index + 2 < bytes.len() {
                let hex = &encoded_path[index + 1..index + 3];
                if let Ok(byte) = u8::from_str_radix(hex, 16) {
                    output.push(byte);
                    index += 3;
                    continue;
                }
            }
            output.push(bytes[index]);
            index += 1;
        }
        String::from_utf8_lossy(&output).into_owned()
    } else {
        raw.to_owned()
    };
    if let Some(relative) = decoded.strip_prefix("~/") {
        if let Some(home) = env::var_os("HOME") {
            return PathBuf::from(home).join(relative);
        }
    }
    PathBuf::from(decoded)
}

fn is_video(path: &Path) -> bool {
    path.extension()
        .and_then(|value| value.to_str())
        .is_some_and(|value| {
            ["mp4", "webm", "mkv", "avi", "mov"].contains(&value.to_lowercase().as_str())
        })
}

fn source_image_for_wallpaper(wallpaper: &Path, cfg: &Value) -> Result<PathBuf, String> {
    if !is_video(wallpaper) {
        return Ok(wallpaper.to_owned());
    }
    if !wallpaper.is_file() {
        return Err(format!(
            "Video wallpaper not found: {}",
            wallpaper.display()
        ));
    }
    if local_path(string_at(cfg, "background.wallpaperPath")) == wallpaper {
        let thumbnail = local_path(string_at(cfg, "background.thumbnailPath"));
        if thumbnail.is_file() {
            return Ok(thumbnail);
        }
    }
    let preview_dir =
        xdg_path("XDG_CACHE_HOME", ".cache")?.join("nyvorel-appearance-studio/video-previews");
    fs::create_dir_all(&preview_dir).map_err(|error| error.to_string())?;
    let path_string = wallpaper.to_string_lossy();
    let digest = sha256_hex(path_string.as_bytes());
    let stem = wallpaper
        .file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or("wallpaper");
    let output = preview_dir.join(format!("{stem}-{}.jpg", &digest[..12]));
    if output.is_file() && fs::metadata(&output).is_ok_and(|meta| meta.len() > 0) {
        return Ok(output);
    }
    let mut command = Command::new("ffmpeg");
    command
        .args(["-y", "-ss", "0", "-i"])
        .arg(wallpaper)
        .args(["-frames:v", "1"])
        .arg(&output);
    if !run_bounded(command, Duration::from_secs(30))? || !output.is_file() {
        return Err("Could not extract a frame from video wallpaper".into());
    }
    Ok(output)
}

fn variant_palettes(wallpaper_arg: &str, mode: &str) -> Result<Value, String> {
    let cfg = read_json(&config_path()?);
    let wallpaper = if wallpaper_arg.is_empty() {
        string_at(&cfg, "background.wallpaperPath")
    } else {
        wallpaper_arg
    };
    let wallpaper_path = local_path(wallpaper);
    if wallpaper.is_empty() || !wallpaper_path.is_file() {
        return Ok(
            json!({"ok": true, "sourceColor": "", "variants": [], "error": "Wallpaper is unavailable"}),
        );
    }
    let source_image = match source_image_for_wallpaper(&wallpaper_path, &cfg) {
        Ok(path) => path,
        Err(error) => {
            return Ok(json!({"ok": true, "sourceColor": "", "variants": [], "error": error}))
        }
    };
    let base_mode = if mode == "light" { "light" } else { "dark" };
    let catalog: Value = serde_json::from_str(CATALOG).map_err(|error| error.to_string())?;
    let matrix = match intelligence::matrix(&source_image, base_mode, mode, &catalog["schemes"]) {
        Ok(matrix) => matrix,
        Err(error) => {
            return Ok(json!({"ok": true, "sourceColor": "", "variants": [], "error": error}))
        }
    };
    let evaluations = matrix["evaluations"]
        .as_array()
        .ok_or("Invalid intelligence evaluations")?;
    let best = &matrix["best"];
    let auto_scheme = best["scheme"]
        .as_str()
        .ok_or("Intelligence result lacks a scheme")?;
    let auto_seed = best["seed"]
        .as_str()
        .ok_or("Intelligence result lacks a seed")?;
    let mut variants = Vec::<Value>::new();
    let mut errors = Vec::<String>::new();
    for scheme in catalog["schemes"].as_array().into_iter().flatten() {
        let Some(id) = scheme["id"].as_str() else {
            continue;
        };
        if id == "auto" {
            continue;
        }
        let Some(choice) = evaluations.iter().find(|entry| entry["scheme"] == id) else {
            errors.push(format!("{id}: no generated candidate"));
            continue;
        };
        let full = &choice["visiblePalette"];
        variants.push(json!({
            "id": id,
            "name": scheme["name"],
            "seed": choice["seed"],
            "score": choice["score"],
            "reason": choice["reason"],
            "metrics": choice["metrics"],
            "colors": {
                "primary": full["primary"],
                "secondary": full["secondary"],
                "tertiary": full["tertiary"],
                "surface": full.get("surface_container").unwrap_or(&full["surface"]),
                "onSurface": full["on_surface"],
            },
        }));
    }
    if let Some(source) = variants
        .iter()
        .find(|item| item["id"] == auto_scheme && item["seed"] == auto_seed)
        .or_else(|| variants.iter().find(|item| item["id"] == auto_scheme))
    {
        let mut automatic = source.clone();
        automatic["id"] = json!("auto");
        automatic["name"] = json!("Auto");
        automatic["resolvedScheme"] = json!(auto_scheme);
        automatic["resolvedSeed"] = json!(auto_seed);
        automatic["score"] = best["score"].clone();
        automatic["reason"] = best["reason"].clone();
        automatic["metrics"] = best["metrics"].clone();
        variants.insert(0, automatic);
    }
    let error = if variants.is_empty() {
        format!(
            "Variant generation failed. {}",
            errors
                .iter()
                .take(3)
                .cloned()
                .collect::<Vec<_>>()
                .join(" | ")
        )
    } else if errors.is_empty() {
        String::new()
    } else {
        format!("{} variant preview(s) could not be generated", errors.len())
    };
    Ok(json!({
        "ok": true,
        "wallpaper": wallpaper,
        "sourceImage": source_image.display().to_string(),
        "sourceColor": auto_seed,
        "baseMode": base_mode,
        "autoScheme": auto_scheme,
        "variants": variants,
        "error": error,
        "intelligence": {
            "engine": "semantic-palette-score-rust-v2",
            "candidateSeeds": matrix["seeds"],
            "profile": matrix["profile"],
            "autoScore": best["score"],
            "autoReason": best["reason"],
            "errors": matrix["errors"],
        }
    }))
}

fn read_json(path: &Path) -> Value {
    fs::read(path)
        .ok()
        .and_then(|data| serde_json::from_slice(&data).ok())
        .unwrap_or_else(|| json!({}))
}

fn get_nested<'a>(value: &'a Value, dotted: &str) -> Option<&'a Value> {
    dotted.split('.').try_fold(value, |node, key| node.get(key))
}

fn set_nested(value: &mut Value, dotted: &str, replacement: Value) {
    let mut node = value;
    let mut parts = dotted.split('.').peekable();
    while let Some(part) = parts.next() {
        if parts.peek().is_none() {
            if let Some(map) = node.as_object_mut() {
                map.insert(part.to_owned(), replacement);
            }
            return;
        }
        if !node.get(part).is_some_and(Value::is_object) {
            node[part] = json!({});
        }
        node = &mut node[part];
    }
}

fn string_at<'a>(value: &'a Value, dotted: &str) -> &'a str {
    get_nested(value, dotted)
        .and_then(Value::as_str)
        .unwrap_or("")
}

fn is_truthy(value: &Value) -> bool {
    match value {
        Value::Null => false,
        Value::Bool(value) => *value,
        Value::Number(value) => value.as_f64().is_some_and(|n| n != 0.0),
        Value::String(value) => !value.is_empty(),
        Value::Array(value) => !value.is_empty(),
        Value::Object(value) => !value.is_empty(),
    }
}

fn migrate_legacy_style(cfg: &mut Value, catalog: &Value) {
    let style = string_at(cfg, "appearance.interfaceStyle")
        .trim()
        .to_lowercase();
    if let Some(alias) = catalog["legacyAliases"].get(&style).and_then(Value::as_str) {
        set_nested(cfg, "appearance.interfaceStyle", json!(alias));
    }
}

fn ensure_radius(cfg: &mut Value, catalog: &Value) {
    let defaults = &catalog["radiusDefaults"];
    if get_nested(cfg, "appearance.geometry.radius.global").is_none_or(Value::is_null) {
        set_nested(
            cfg,
            "appearance.geometry.radius.global",
            defaults["global"].clone(),
        );
    }
    if let Some(roles) = catalog["radiusRoles"].as_array() {
        for role in roles.iter().filter_map(Value::as_str) {
            for field in ["followGlobal", "value"] {
                let dotted = format!("appearance.geometry.radius.{role}.{field}");
                if get_nested(cfg, &dotted).is_none() {
                    set_nested(cfg, &dotted, defaults[role][field].clone());
                }
            }
        }
    }
}

fn snapshot(cfg: &Value, catalog: &Value) -> Value {
    let mut cfg = cfg.clone();
    ensure_radius(&mut cfg, catalog);
    let mut result = Map::new();
    if let Some(keys) = catalog["snapshotKeys"].as_array() {
        for key in keys.iter().filter_map(Value::as_str) {
            result.insert(
                key.to_owned(),
                get_nested(&cfg, key).cloned().unwrap_or(Value::Null),
            );
        }
    }
    Value::Object(result)
}

fn detect_profile(cfg: &Value, catalog: &Value) -> String {
    let explicit_style =
        is_truthy(get_nested(cfg, "appearance.interfaceStyle").unwrap_or(&Value::Null));
    if let Some(profiles) = catalog["uiProfiles"].as_array() {
        for allow_legacy in [false, true] {
            if allow_legacy && explicit_style {
                break;
            }
            for profile in profiles {
                let Some(id) = profile["id"].as_str() else {
                    continue;
                };
                let Some(patch) = profile["patch"].as_object() else {
                    continue;
                };
                let matches = !patch.is_empty()
                    && patch.iter().all(|(key, expected)| {
                        (allow_legacy && key == "appearance.interfaceStyle")
                            || get_nested(cfg, key).unwrap_or(&Value::Null) == expected
                    });
                if matches {
                    return id.to_owned();
                }
            }
        }
    }
    "custom".to_owned()
}

fn radius(cfg: &Value, catalog: &Value, role: &str) -> i64 {
    let global = get_nested(cfg, "appearance.geometry.radius.global")
        .and_then(Value::as_i64)
        .unwrap_or(17)
        .clamp(0, 48);
    if role == "global" {
        return global;
    }
    let prefix = format!("appearance.geometry.radius.{role}");
    if get_nested(cfg, &format!("{prefix}.followGlobal")).is_some_and(is_truthy) {
        global
    } else {
        get_nested(cfg, &format!("{prefix}.value"))
            .and_then(Value::as_i64)
            .or_else(|| catalog["radiusDefaults"][role]["value"].as_i64())
            .unwrap_or(global)
            .clamp(0, 48)
    }
}

fn fingerprint(active: &Value, ui: &Value) -> Result<String, String> {
    let payload = json!({"active": active, "ui": ui});
    let encoded = serde_json::to_vec(&payload).map_err(|err| err.to_string())?;
    Ok(sha256_hex(&encoded)[..20].to_owned())
}

fn system_mode() -> &'static str {
    let child = Command::new("gsettings")
        .args(["get", "org.gnome.desktop.interface", "color-scheme"])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn();
    let Ok(mut child) = child else {
        return "dark";
    };
    let deadline = Instant::now() + Duration::from_secs(2);
    loop {
        match child.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(10)),
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                return "dark";
            }
        }
    }
    child
        .wait_with_output()
        .map(|output| {
            if String::from_utf8_lossy(&output.stdout).contains("dark") {
                "dark"
            } else {
                "light"
            }
        })
        .unwrap_or("dark")
}

fn first_run_state(cfg: &Value, catalog: &Value) -> Value {
    let system_mode = system_mode();
    let hyprland = env::var("XDG_CURRENT_DESKTOP")
        .unwrap_or_default()
        .to_lowercase()
        .contains("hyprland")
        || env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_some_and(|value| !value.is_empty());
    let theme_cfg = get_nested(cfg, "appearance.wallpaperTheming").unwrap_or(&Value::Null);
    let palette = get_nested(cfg, "appearance.palette").unwrap_or(&Value::Null);
    let scheme = palette["type"]
        .as_str()
        .filter(|value| !value.is_empty())
        .unwrap_or("auto");
    json!({
        "version": 4,
        "active": {
            "source": "wallpaper",
            "preset": "",
            "seed": "",
            "scheme": scheme,
            "mode": system_mode,
            "wallpaper": string_at(cfg, "background.wallpaperPath"),
            "uiProfile": detect_profile(cfg, catalog),
        },
        "targets": {
            "shell": true,
            "hyprland": true,
            "hyprlock": true,
            "gtk": true,
            "fuzzel": true,
            "qt": theme_cfg["enableQtApps"].as_bool().unwrap_or(true) && !hyprland,
            "terminal": theme_cfg["enableTerminal"].as_bool().unwrap_or(true),
            "editors": true,
        },
        "activeUi": snapshot(cfg, catalog),
        "favorites": [],
        "history": [],
        "preview": null,
    })
}

fn load_state(cfg: &Value, catalog: &Value) -> Result<Value, String> {
    let path = state_path()?;
    if !path.is_file() {
        return Ok(first_run_state(cfg, catalog));
    }
    let mut state = read_json(&path);
    if !state.is_object() {
        state = json!({});
    }
    let needs_defaults = [
        "active",
        "targets",
        "activeUi",
        "favorites",
        "history",
        "preview",
    ]
    .iter()
    .any(|key| state.get(*key).is_none())
        || [
            "shell", "hyprland", "hyprlock", "gtk", "fuzzel", "qt", "terminal", "editors",
        ]
        .iter()
        .any(|key| state["targets"].get(*key).is_none());
    let defaults = if needs_defaults {
        first_run_state(cfg, catalog)
    } else {
        Value::Null
    };
    for key in [
        "active",
        "targets",
        "activeUi",
        "favorites",
        "history",
        "preview",
    ] {
        if state.get(key).is_none() {
            state[key] = defaults[key].clone();
        }
    }
    if !state["targets"].is_object() {
        return Err("invalid Appearance Studio targets".into());
    }
    for key in [
        "shell", "hyprland", "hyprlock", "gtk", "fuzzel", "qt", "terminal", "editors",
    ] {
        if state["targets"].get(key).is_none() {
            state["targets"][key] = defaults["targets"][key].clone();
        }
    }
    if !state["activeUi"].is_object() {
        state["activeUi"] = snapshot(cfg, catalog);
    }
    for (path, key) in [
        ("active", "uiProfile"),
        ("activeUi", "appearance.interfaceStyle"),
    ] {
        let old = state[path][key]
            .as_str()
            .unwrap_or("")
            .trim()
            .to_lowercase();
        if let Some(alias) = catalog["legacyAliases"].get(&old).and_then(Value::as_str) {
            state[path][key] = json!(alias);
        }
    }
    state["version"] = json!(4);
    Ok(state)
}

fn status() -> Result<Value, String> {
    let catalog: Value = serde_json::from_str(CATALOG).map_err(|err| err.to_string())?;
    let mut cfg = read_json(&config_path()?);
    migrate_legacy_style(&mut cfg, &catalog);
    let state = load_state(&cfg, &catalog)?;
    let ui = snapshot(&cfg, &catalog);
    if !state["active"].is_object() {
        return Err("invalid Appearance Studio active state".into());
    }
    let preview = state.get("preview").cloned().unwrap_or(Value::Null);
    let mut active = state["active"].clone();
    let committed_ui = if is_truthy(&preview) {
        let profile = string_at(&active, "uiProfile").trim().to_lowercase();
        if let Some(alias) = catalog["legacyAliases"]
            .get(&profile)
            .and_then(Value::as_str)
        {
            active["uiProfile"] = json!(alias);
        }
        state["activeUi"].clone()
    } else {
        let wallpaper = string_at(&cfg, "background.wallpaperPath").to_owned();
        let scheme = string_at(&cfg, "appearance.palette.type").to_owned();
        let accent = string_at(&cfg, "appearance.palette.accentColor").to_owned();
        let old_wallpaper = string_at(&active, "wallpaper").to_owned();
        if !wallpaper.is_empty() {
            active["wallpaper"] = json!(wallpaper);
        }
        if !scheme.is_empty() {
            active["scheme"] = json!(scheme);
        }
        active["uiProfile"] = json!(detect_profile(&cfg, &catalog));
        if !wallpaper.is_empty() && wallpaper != old_wallpaper && accent.is_empty() {
            active["source"] = json!("wallpaper");
            active["preset"] = json!("");
            active["seed"] = json!("");
        } else if !accent.is_empty() && ["preset", "custom"].contains(&string_at(&active, "source"))
        {
            active["seed"] = json!(accent.to_lowercase());
        }
        ui.clone()
    };
    let active_ui_style = string_at(&committed_ui, "appearance.interfaceStyle")
        .trim()
        .to_lowercase();
    let committed_ui = if let Some(alias) = catalog["legacyAliases"]
        .get(&active_ui_style)
        .and_then(Value::as_str)
    {
        let mut next = committed_ui;
        next["appearance.interfaceStyle"] = json!(alias);
        next
    } else {
        committed_ui
    };
    let mut geometry = Map::new();
    geometry.insert("global".into(), json!(radius(&cfg, &catalog, "global")));
    if let Some(roles) = catalog["radiusRoles"].as_array() {
        for role in roles.iter().filter_map(Value::as_str) {
            geometry.insert(role.to_owned(), json!(radius(&cfg, &catalog, role)));
        }
    }
    Ok(json!({
        "ok": true,
        "version": 4,
        "studioVersion": "0.3.2",
        "wallpaper": string_at(&cfg, "background.wallpaperPath"),
        "committedWallpaper": string_at(&active, "wallpaper"),
        "thumbnail": string_at(&cfg, "background.thumbnailPath"),
        "palette": get_nested(&cfg, "appearance.palette").cloned().unwrap_or(json!({})),
        "colors": read_json(&colors_path()?),
        "active": active,
        "activeUi": committed_ui,
        "currentFingerprint": fingerprint(&active, &committed_ui)?,
        "targets": state["targets"],
        "favorites": state.get("favorites").cloned().unwrap_or(json!([])),
        "history": state.get("history").cloned().unwrap_or(json!([])),
        "preview": preview,
        "previewTimeout": 15,
        "presets": catalog["presets"],
        "schemes": catalog["schemes"],
        "modes": catalog["modes"],
        "uiProfiles": catalog["uiProfiles"],
        "ui": ui,
        "geometry": geometry,
        "semantics": {
            "previewScope": "quickshell-and-interface-only",
            "hybridExternalTargets": "wallpaper-accent",
            "specialModesExternalTargets": "dark-material-base"
        }
    }))
}

struct MutationLock(File);

impl MutationLock {
    fn acquire() -> Result<Self, String> {
        let path = lock_path()?;
        fs::create_dir_all(path.parent().ok_or("invalid lock path")?)
            .map_err(|err| err.to_string())?;
        let file = OpenOptions::new()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .open(path)
            .map_err(|err| err.to_string())?;
        let deadline = Instant::now() + Duration::from_secs(12);
        loop {
            // SAFETY: flock operates on the valid, open descriptor owned by file.
            let result = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
            if result == 0 {
                return Ok(Self(file));
            }
            if io::Error::last_os_error().raw_os_error() != Some(libc::EWOULDBLOCK) {
                return Err(format!(
                    "Could not lock Appearance Studio: {}",
                    io::Error::last_os_error()
                ));
            }
            if Instant::now() >= deadline {
                return Err("Appearance Studio is busy; try again in a moment".into());
            }
            std::thread::sleep(Duration::from_millis(50));
        }
    }
}

impl Drop for MutationLock {
    fn drop(&mut self) {
        // SAFETY: descriptor remains open through this call.
        unsafe { libc::flock(self.0.as_raw_fd(), libc::LOCK_UN) };
    }
}

fn atomic_json_write(path: &Path, value: &Value) -> Result<(), String> {
    let parent = path.parent().ok_or("invalid state path")?;
    fs::create_dir_all(parent).map_err(|err| err.to_string())?;
    let mut rendered = serde_json::to_vec_pretty(value).map_err(|err| err.to_string())?;
    rendered.push(b'\n');
    if fs::read(path).is_ok_and(|old| old == rendered) {
        return Ok(());
    }
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|err| err.to_string())?
        .as_nanos();
    let tmp = parent.join(format!(
        ".appearance-studio.{}.{}.tmp",
        process::id(),
        nonce
    ));
    let result = (|| -> Result<(), String> {
        let mut file = OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(&tmp)
            .map_err(|err| err.to_string())?;
        let mode = fs::metadata(path)
            .ok()
            .map(|meta| meta.permissions().mode())
            .unwrap_or(0o600);
        fs::set_permissions(&tmp, fs::Permissions::from_mode(mode))
            .map_err(|err| err.to_string())?;
        file.write_all(&rendered).map_err(|err| err.to_string())?;
        file.sync_all().map_err(|err| err.to_string())?;
        fs::rename(&tmp, path).map_err(|err| err.to_string())?;
        File::open(parent)
            .and_then(|file| file.sync_all())
            .map_err(|err| err.to_string())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&tmp);
    }
    result
}

fn simple_mutation(command: &str, args: &[String]) -> Result<Value, String> {
    if (command == "clear-history" && args.len() != 1)
        || (command == "favorite-remove" && args.len() != 2)
    {
        return Err("legacy argument validation required".into());
    }
    let _lock = MutationLock::acquire()?;
    let path = state_path()?;
    let catalog: Value = serde_json::from_str(CATALOG).map_err(|error| error.to_string())?;
    let mut cfg = read_json(&config_path()?);
    migrate_legacy_style(&mut cfg, &catalog);
    let mut state = load_state(&cfg, &catalog)?;
    match command {
        "clear-history" => state["history"] = json!([]),
        "favorite-remove" => {
            let id = args.get(1).ok_or("missing favorite ID")?;
            let favorites = state["favorites"]
                .as_array()
                .ok_or("invalid favorites list")?;
            state["favorites"] = Value::Array(
                favorites
                    .iter()
                    .filter(|entry| entry["id"] != *id)
                    .cloned()
                    .collect(),
            );
        }
        _ => return Err("unsupported native mutation".into()),
    }
    atomic_json_write(&path, &state)?;
    Ok(json!({"ok": true}))
}

fn wallpaper_stem(value: &str) -> String {
    Path::new(value)
        .file_stem()
        .and_then(|stem| stem.to_str())
        .filter(|stem| !stem.is_empty())
        .unwrap_or("Wallpaper")
        .to_owned()
}

fn favorite_label(active: &Value, catalog: &Value) -> String {
    let source = active["source"].as_str().unwrap_or("wallpaper");
    let preset_name = || {
        catalog["presets"]
            .as_array()
            .and_then(|presets| {
                presets
                    .iter()
                    .find(|preset| preset["id"].as_str() == active["preset"].as_str())
            })
            .and_then(|preset| preset["name"].as_str())
            .unwrap_or("Preset")
    };
    let source_name = match source {
        "preset" => preset_name().to_owned(),
        "hybrid" => format!(
            "{} + {}",
            wallpaper_stem(string_at(active, "wallpaper")),
            preset_name()
        ),
        "custom" => active["seed"].as_str().unwrap_or("Custom").to_owned(),
        _ => wallpaper_stem(string_at(active, "wallpaper")),
    };
    let scheme = active["scheme"].as_str().unwrap_or("Theme");
    let scheme_name = catalog["schemes"]
        .as_array()
        .and_then(|schemes| {
            schemes
                .iter()
                .find(|item| item["id"].as_str() == Some(scheme))
        })
        .and_then(|item| item["name"].as_str())
        .unwrap_or(scheme);
    let mode = active["mode"].as_str().unwrap_or("dark");
    let titled = mode
        .split('-')
        .map(|part| {
            let mut chars = part.chars();
            match chars.next() {
                Some(first) => {
                    first.to_uppercase().collect::<String>() + &chars.as_str().to_lowercase()
                }
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join("-");
    format!("{source_name} · {scheme_name} · {titled}")
}

fn random_id() -> Result<String, String> {
    let mut bytes = [0_u8; 6];
    File::open("/dev/urandom")
        .and_then(|mut file| file.read_exact(&mut bytes))
        .map_err(|err| format!("Could not generate favorite ID: {err}"))?;
    let mut result = String::with_capacity(12);
    for byte in bytes {
        use std::fmt::Write as _;
        write!(&mut result, "{byte:02x}").expect("writing to String cannot fail");
    }
    Ok(result)
}

fn favorite_add(args: &[String]) -> Result<Value, String> {
    let label = match args {
        [_] => "",
        [_, flag, value] if flag == "--label" => value,
        _ => return Err("unsupported favorite-add arguments".into()),
    };
    let _lock = MutationLock::acquire()?;
    let path = state_path()?;
    let catalog: Value = serde_json::from_str(CATALOG).map_err(|err| err.to_string())?;
    let cfg = read_json(&config_path()?);
    let mut state = load_state(&cfg, &catalog)?;
    let current = status()?;
    if is_truthy(&current["preview"]) {
        return Err("Keep or Revert the preview before saving a favorite".into());
    }
    let active = current["active"].clone();
    let ui = current["activeUi"].clone();
    let fp = fingerprint(&active, &ui)?;
    let id = random_id()?;
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|err| err.to_string())?
        .as_secs();
    let mut entry = json!({
        "id": id,
        "timestamp": timestamp,
        "label": favorite_label(&active, &catalog),
        "customLabel": false,
        "fingerprint": fp,
        "active": active,
        "colors": current["colors"],
        "ui": ui,
    });
    if !label.is_empty() {
        entry["label"] = json!(label);
        entry["customLabel"] = json!(true);
    }
    let existing = state["favorites"]
        .as_array()
        .ok_or("invalid favorites list")?;
    let mut favorites = Vec::with_capacity(existing.len().min(29) + 1);
    favorites.push(entry.clone());
    for saved in existing {
        let saved_fp = if let Some(fp) = saved["fingerprint"].as_str().filter(|fp| !fp.is_empty()) {
            fp.to_owned()
        } else {
            fingerprint(&saved["active"], &saved["ui"])?
        };
        if saved_fp != fp || saved["label"] != entry["label"] {
            if favorites.len() == 30 {
                break;
            }
            favorites.push(saved.clone());
        }
    }
    state["active"] = active;
    state["activeUi"] = ui;
    state["favorites"] = Value::Array(favorites);
    atomic_json_write(&path, &state)?;
    Ok(json!({"ok": true, "favorite": entry}))
}

fn target_change(args: &[String]) -> Result<Value, String> {
    let name = args.get(1).ok_or("missing target name")?;
    let enabled = matches!(args.get(2).map(String::as_str), Some("true" | "1"));
    let _lock = MutationLock::acquire()?;
    let path = state_path()?;
    let catalog: Value = serde_json::from_str(CATALOG).map_err(|err| err.to_string())?;
    let cfg = read_json(&config_path()?);
    let mut state = load_state(&cfg, &catalog)?;
    if !state["targets"][name].is_boolean() {
        return Err(format!("Unknown target: {name}"));
    }
    let previous = state["targets"][name].as_bool().unwrap_or(true);
    if enabled && !previous {
        return Err("legacy theme reapply required".into());
    }
    if !is_truthy(&state["preview"]) {
        let current = status()?;
        state["active"] = current["active"].clone();
        state["activeUi"] = current["activeUi"].clone();
    }
    state["targets"][name] = json!(enabled);
    let mut config_update = None;
    if name == "qt" || name == "terminal" {
        let cfg_path = config_path()?;
        let mut cfg = read_json(&cfg_path);
        let catalog: Value = serde_json::from_str(CATALOG).map_err(|err| err.to_string())?;
        migrate_legacy_style(&mut cfg, &catalog);
        let flag = if name == "qt" {
            "enableQtApps"
        } else {
            "enableTerminal"
        };
        set_nested(
            &mut cfg,
            &format!("appearance.wallpaperTheming.{flag}"),
            json!(enabled),
        );
        config_update = Some((cfg_path, cfg));
    }
    if let Some((cfg_path, cfg)) = config_update {
        let snapshot = transaction::Snapshot::capture(&[&path, &cfg_path])?;
        let write_result =
            atomic_json_write(&path, &state).and_then(|_| atomic_json_write(&cfg_path, &cfg));
        if let Err(error) = write_result {
            return match snapshot.restore() {
                Ok(()) => Err(error),
                Err(rollback_error) => {
                    Err(format!("{error}; rollback also failed: {rollback_error}"))
                }
            };
        }
    } else {
        atomic_json_write(&path, &state)?;
    }
    Ok(
        json!({"ok": true, "target": name, "enabled": enabled, "synchronized": false, "warnings": []}),
    )
}

fn run_bounded(mut command: Command, timeout: Duration) -> Result<bool, String> {
    command
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    let mut child = command.spawn().map_err(|error| error.to_string())?;
    let deadline = Instant::now() + timeout;
    loop {
        match child.try_wait() {
            Ok(Some(status)) => return Ok(status.success()),
            Ok(None) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(20)),
            Ok(None) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err("Appearance helper timed out".into());
            }
            Err(error) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(format!("Could not wait for appearance helper: {error}"));
            }
        }
    }
}

fn restore_gsettings(preview: &Path) {
    let values = read_json(&preview.join("gsettings.json"));
    for key in ["color-scheme", "gtk-theme"] {
        let Some(value) = values[key].as_str().filter(|value| !value.is_empty()) else {
            continue;
        };
        let mut command = Command::new("gsettings");
        command.args([
            "set",
            "org.gnome.desktop.interface",
            key,
            value.trim_matches(['\'', '"']),
        ]);
        let _ = run_bounded(command, Duration::from_secs(3));
    }
}

fn runtime_modes(cfg: &Value, catalog: &Value) -> (bool, bool) {
    (
        get_nested(cfg, "appearance.transparency.enable").is_some_and(is_truthy),
        detect_profile(cfg, catalog) == "fluid",
    )
}

fn sync_runtime_best_effort(cfg: &Value, catalog: &Value) {
    let home = match env::var_os("HOME") {
        Some(home) => PathBuf::from(home),
        None => return,
    };
    let (glass, fluid) = runtime_modes(cfg, catalog);
    for (path, mode) in [
        (
            home.join(".local/bin/nyvorel-glass-runtime"),
            if glass { "glass" } else { "default" },
        ),
        (
            home.join(".local/bin/nyvorel-fluid-runtime"),
            if fluid { "fluid" } else { "default" },
        ),
    ] {
        if path.is_file() {
            let mut command = Command::new(&path);
            command.arg(mode);
            let _ = run_bounded(command, Duration::from_secs(20));
        }
    }
}

fn restore_preview_runtime(preview: &Path, catalog: &Value) -> Result<(), String> {
    let cfg_before = read_json(&config_path()?);
    let snapshot = transaction::Snapshot::from_preview(preview, &preview_allowed_paths()?)?;
    snapshot.restore()?;
    restore_gsettings(preview);
    let cfg_after = read_json(&config_path()?);
    if runtime_modes(&cfg_before, catalog) != runtime_modes(&cfg_after, catalog) {
        sync_runtime_best_effort(&cfg_after, catalog);
        let rules =
            xdg_path("XDG_CONFIG_HOME", ".config")?.join("hypr/custom/appearance-runtime.lua");
        let before_second_restore = fs::read(&rules).ok();
        snapshot.restore()?;
        if before_second_restore != fs::read(&rules).ok() {
            let mut command = Command::new("hyprctl");
            command.arg("reload");
            let _ = run_bounded(command, Duration::from_secs(8));
        }
    }
    Ok(())
}

fn revert_preview_locked() -> Result<Value, String> {
    let catalog: Value = serde_json::from_str(CATALOG).map_err(|error| error.to_string())?;
    let config = read_json(&config_path()?);
    let mut state = load_state(&config, &catalog)?;
    let preview = preview_path()?;
    if !preview.exists() {
        state["preview"] = Value::Null;
        atomic_json_write(&state_path()?, &state)?;
        return Ok(json!({"ok": true, "message": "No preview snapshot was found"}));
    }
    let baseline_path = preview.join("state-before.json");
    let mut baseline: Value = serde_json::from_slice(
        &fs::read(&baseline_path).map_err(|error| format!("Missing preview baseline: {error}"))?,
    )
    .map_err(|error| format!("Invalid preview baseline: {error}"))?;
    if !baseline.is_object() || !baseline["active"].is_object() {
        return Err("Invalid preview baseline state".into());
    }
    for key in ["targets", "favorites", "history"] {
        if let Some(value) = state.get(key) {
            baseline[key] = value.clone();
        }
    }
    baseline["version"] = json!(4);
    baseline["preview"] = Value::Null;
    restore_preview_runtime(&preview, &catalog)?;
    let config_path = config_path()?;
    let mut restored_config = read_json(&config_path);
    for (target, flag) in [("qt", "enableQtApps"), ("terminal", "enableTerminal")] {
        set_nested(
            &mut restored_config,
            &format!("appearance.wallpaperTheming.{flag}"),
            json!(baseline["targets"][target].as_bool().unwrap_or(true)),
        );
    }
    atomic_json_write(&config_path, &restored_config)?;
    atomic_json_write(&state_path()?, &baseline)?;
    fs::remove_dir_all(&preview).map_err(|error| error.to_string())?;
    Ok(json!({"ok": true, "reverted": true, "active": baseline["active"]}))
}

fn revert_preview() -> Result<Value, String> {
    let _lock = MutationLock::acquire()?;
    revert_preview_locked()
}

fn epoch_seconds() -> Result<f64, String> {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs_f64())
        .map_err(|error| error.to_string())
}

fn preview_watchdog(token: &str, revision: i64) -> Result<Value, String> {
    loop {
        let catalog: Value = serde_json::from_str(CATALOG).map_err(|error| error.to_string())?;
        let config = read_json(&config_path()?);
        let state = load_state(&config, &catalog)?;
        let preview = &state["preview"];
        if preview["token"].as_str() != Some(token)
            || preview["revision"].as_i64() != Some(revision)
        {
            return Ok(json!({"ok": true, "expired": false}));
        }
        let remaining = preview["expiresAt"].as_f64().unwrap_or(0.0) - epoch_seconds()?;
        if remaining > 0.0 {
            std::thread::sleep(Duration::from_secs_f64((remaining + 0.05).min(5.0)));
            continue;
        }
        let _lock = MutationLock::acquire()?;
        let config = read_json(&config_path()?);
        let state = load_state(&config, &catalog)?;
        let preview = &state["preview"];
        if preview["token"].as_str() == Some(token)
            && preview["revision"].as_i64() == Some(revision)
            && epoch_seconds()? >= preview["expiresAt"].as_f64().unwrap_or(0.0)
        {
            return revert_preview_locked();
        }
        return Ok(json!({"ok": true, "expired": false}));
    }
}

fn print_result(result: Result<Value, String>) -> i32 {
    match result {
        Ok(value) => {
            println!("{value}");
            0
        }
        Err(error) => {
            println!("{}", json!({"ok": false, "error": error}));
            1
        }
    }
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let result = match args.first().map(String::as_str) {
        Some("__semantic-radius") => match semantic_radius::run(&args[1..]) {
            Ok(()) => 0,
            Err(error) => {
                eprintln!("{error}");
                1
            }
        },
        Some("__kvantum-svg") if args.len() == 2 => match kvantum::svg(&args[1]) {
            Ok(()) => 0,
            Err(error) => {
                eprintln!("{error}");
                1
            }
        },
        Some("__kvantum-config") if args.len() == 1 => match kvantum::config() {
            Ok(()) => 0,
            Err(error) => {
                eprintln!("{error}");
                1
            }
        },
        Some("__scheme-for-image") => match color_image::scheme(&args[1..]) {
            Ok(scheme) => {
                println!("{scheme}");
                0
            }
            Err(error) => {
                eprintln!("{error}");
                1
            }
        },
        Some("__material-scss") => match material_scss::render(&args[1..]) {
            Ok(scss) => {
                print!("{scss}");
                0
            }
            Err(error) => {
                eprintln!("{error}");
                1
            }
        },
        Some("__resolve") if args.len() == 1 => {
            let mut input = String::new();
            let value = io::stdin()
                .read_to_string(&mut input)
                .map_err(|error| error.to_string())
                .and_then(|_| {
                    serde_json::from_str::<Value>(&input).map_err(|error| error.to_string())
                })
                .and_then(|draft| {
                    let catalog = serde_json::from_str::<Value>(CATALOG)
                        .map_err(|error| error.to_string())?;
                    request::resolve(&draft, &read_json(&config_path()?), &catalog)
                });
            print_result(value)
        }
        Some("__render-colors") if args.len() == 1 => {
            let mut input = String::new();
            let value = io::stdin()
                .read_to_string(&mut input)
                .map_err(|error| error.to_string())
                .and_then(|_| {
                    serde_json::from_str::<Value>(&input).map_err(|error| error.to_string())
                })
                .and_then(|resolved| request::generate_palette(&resolved));
            print_result(value)
        }
        Some("__variants") if args.len() == 3 => print_result(variant_palettes(&args[1], &args[2])),
        Some("__matrix") if args.len() == 4 => {
            let catalog = serde_json::from_str::<Value>(CATALOG).map_err(|error| error.to_string());
            print_result(catalog.and_then(|catalog| {
                intelligence::matrix(Path::new(&args[1]), &args[2], &args[3], &catalog["schemes"])
            }))
        }
        Some("__profile") if args.len() == 2 => {
            print_result(intelligence::profile(Path::new(&args[1])))
        }
        Some("__score") if args.len() == 1 => {
            let mut input = String::new();
            let value = io::stdin()
                .read_to_string(&mut input)
                .map_err(|error| error.to_string())
                .and_then(|_| {
                    serde_json::from_str::<Value>(&input).map_err(|error| error.to_string())
                })
                .and_then(|data| {
                    intelligence::score(
                        &data["profile"],
                        &data["palette"],
                        data["seed"].as_str().unwrap_or(""),
                    )
                });
            print_result(value)
        }
        Some("__special-mode") if args.len() == 2 => {
            let mut input = String::new();
            let value = io::stdin()
                .read_to_string(&mut input)
                .map_err(|error| error.to_string())
                .and_then(|_| {
                    serde_json::from_str::<Value>(&input).map_err(|error| error.to_string())
                })
                .map(|colors| modes::apply(&colors, &args[1]));
            print_result(value)
        }
        Some("__palette") if args.len() == 4 => {
            let base_mode = match args[3].as_str() {
                "dim" | "oled" | "high-contrast" => "dark",
                other => other,
            };
            print_result(
                palette::generate(&args[1], &args[2], base_mode)
                    .map(|colors| modes::apply(&colors, &args[3])),
            )
        }
        Some("status") if args.len() == 1 => print_result(status()),
        Some("clear-history" | "favorite-remove") => print_result(simple_mutation(&args[0], &args)),
        Some("favorite-add") => {
            if args.len() != 1 && (args.len() != 3 || args[1] != "--label") {
                print_result(Err("Invalid favorite-add command".into()))
            } else {
                print_result(favorite_add(&args))
            }
        }
        Some("target") => {
            const NAMES: [&str; 8] = [
                "shell", "hyprland", "hyprlock", "gtk", "fuzzel", "qt", "terminal", "editors",
            ];
            if args.len() != 3
                || !NAMES.contains(&args[1].as_str())
                || !["true", "false", "1", "0"].contains(&args[2].as_str())
            {
                print_result(Err("Invalid target command".into()))
            } else {
                match target_change(&args) {
                    Err(error) if error == "legacy theme reapply required" => {
                        print_result(engine::enable_target(&args[1]))
                    }
                    result => print_result(result),
                }
            }
        }
        Some(
            "variants" | "apply" | "keep-preview" | "favorite-apply" | "history-apply"
            | "ui-profile",
        ) => print_result(engine::execute(&args)),
        Some("revert-preview") if args.len() == 1 => print_result(revert_preview()),
        Some("preview-watchdog")
            if args.len() == 5 && args[1] == "--token" && args[3] == "--revision" =>
        {
            print_result(
                args[4]
                    .parse::<i64>()
                    .map_err(|error| format!("Invalid preview revision: {error}"))
                    .and_then(|revision| preview_watchdog(&args[2], revision)),
            )
        }
        _ => print_result(Err("Unsupported Appearance Studio command".into())),
    };
    process::exit(result);
}
