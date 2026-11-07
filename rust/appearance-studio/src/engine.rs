//! Native Appearance Studio transactions. Every command is one-shot and holds
//! the same file lock used by the previous controller while mutating state.

use crate::{
    atomic_json_write, colors_path, config_path, detect_profile, ensure_radius, epoch_seconds,
    get_nested, is_truthy, load_state, local_path, preview_allowed_paths, preview_path, radius,
    read_json, request, restore_preview_runtime, set_nested, sha256_hex, snapshot,
    source_image_for_wallpaper, state_path, string_at, sync_runtime_best_effort,
    transaction::Snapshot, xdg_path, CATALOG,
};
use serde_json::{json, Value};
use std::collections::HashSet;
use std::env;
use std::fs::{self, File};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

const VIDEO_OPTS: &str = "no-audio loop hwdec=auto scale=bilinear interpolation=no video-sync=display-resample panscan=1.0 video-scale-x=1.0 video-scale-y=1.0 video-align-x=0.5 video-align-y=0.5 load-scripts=no";
const HYBRID_SURFACE_ROLES: &[&str] = &[
    "background",
    "on_background",
    "surface",
    "surface_dim",
    "surface_bright",
    "surface_container_lowest",
    "surface_container_low",
    "surface_container",
    "surface_container_high",
    "surface_container_highest",
    "surface_variant",
    "on_surface",
    "on_surface_variant",
    "outline",
    "outline_variant",
    "inverse_surface",
    "inverse_on_surface",
    "shadow",
    "scrim",
];

fn catalog() -> Result<Value, String> {
    serde_json::from_str(CATALOG).map_err(|error| error.to_string())
}

fn home() -> Result<PathBuf, String> {
    env::var_os("HOME")
        .map(PathBuf::from)
        .ok_or("HOME is unset".into())
}

fn xconfig() -> Result<PathBuf, String> {
    xdg_path("XDG_CONFIG_HOME", ".config")
}

fn xstate() -> Result<PathBuf, String> {
    xdg_path("XDG_STATE_HOME", ".local/state")
}

fn nyvorel_dir() -> Result<PathBuf, String> {
    Ok(xconfig()?.join("quickshell/nyvorel"))
}

fn wallpaper_txt() -> Result<PathBuf, String> {
    Ok(xstate()?.join("quickshell/user/generated/wallpaper/path.txt"))
}

fn video_script() -> Result<PathBuf, String> {
    Ok(xconfig()?.join("nyvorel/video-wallpaper-restore.sh"))
}

fn transaction_paths() -> Result<Vec<PathBuf>, String> {
    let mut paths = preview_allowed_paths()?;
    paths.extend([state_path()?, wallpaper_txt()?, video_script()?]);
    let mut unique = HashSet::new();
    paths.retain(|path| unique.insert(path.clone()));
    Ok(paths)
}

fn capture(paths: &[PathBuf]) -> Result<Snapshot, String> {
    Snapshot::capture(&paths.iter().map(PathBuf::as_path).collect::<Vec<_>>())
}

fn disabled_target_paths(targets: &Value) -> Result<Vec<PathBuf>, String> {
    let base = xconfig()?;
    let generated = xstate()?.join("quickshell/user/generated");
    let mut paths = Vec::new();
    for (name, files) in [
        ("shell", vec![generated.join("colors.json")]),
        ("hyprland", vec![base.join("hypr/hyprland/colors.lua")]),
        ("hyprlock", vec![base.join("hypr/hyprlock/colors.conf")]),
        ("fuzzel", vec![base.join("fuzzel/fuzzel_theme.ini")]),
        (
            "gtk",
            vec![base.join("gtk-3.0/gtk.css"), base.join("gtk-4.0/gtk.css")],
        ),
        (
            "editors",
            [
                "Code",
                "VSCodium",
                "Code - OSS",
                "Code - Insiders",
                "Cursor",
                "Antigravity",
            ]
            .into_iter()
            .map(|editor| base.join(editor).join("User/settings.json"))
            .collect(),
        ),
    ] {
        if !targets[name].as_bool().unwrap_or(true) {
            paths.extend(files);
        }
    }
    Ok(paths)
}

fn all_editor_paths() -> Result<Vec<PathBuf>, String> {
    [
        "Code",
        "VSCodium",
        "Code - OSS",
        "Code - Insiders",
        "Cursor",
        "Antigravity",
    ]
    .into_iter()
    .map(|editor| xconfig().map(|base| base.join(editor).join("User/settings.json")))
    .collect::<Result<Vec<_>, _>>()
}

fn gsettings_snapshot() -> Value {
    let mut result = json!({});
    for key in ["color-scheme", "gtk-theme"] {
        let child = Command::new("gsettings")
            .args(["get", "org.gnome.desktop.interface", key])
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn();
        let Ok(mut child) = child else { continue };
        let deadline = Instant::now() + Duration::from_secs(2);
        loop {
            match child.try_wait() {
                Ok(Some(status)) => {
                    if status.success() {
                        if let Ok(output) = child.wait_with_output() {
                            result[key] = json!(String::from_utf8_lossy(&output.stdout).trim());
                        }
                    }
                    break;
                }
                Ok(None) if Instant::now() < deadline => {
                    std::thread::sleep(Duration::from_millis(10))
                }
                _ => {
                    let _ = child.kill();
                    let _ = child.wait();
                    break;
                }
            }
        }
    }
    result
}

fn restore_gsettings(values: &Value) {
    for key in ["color-scheme", "gtk-theme"] {
        if let Some(value) = values[key].as_str().filter(|s| !s.is_empty()) {
            let mut command = Command::new("gsettings");
            command.args([
                "set",
                "org.gnome.desktop.interface",
                key,
                value.trim_matches(['\'', '"']),
            ]);
            let _ = crate::run_bounded(command, Duration::from_secs(3));
        }
    }
}

fn run_command(mut command: Command, timeout: Duration) -> Result<(), String> {
    let output_dir = xdg_path("XDG_CACHE_HOME", ".cache")?.join("nyvorel-appearance-studio");
    fs::create_dir_all(&output_dir).map_err(|error| error.to_string())?;
    let id = crate::random_id()?;
    let stdout_path = output_dir.join(format!(".command-{id}.out"));
    let stderr_path = output_dir.join(format!(".command-{id}.err"));
    let result = (|| -> Result<(), String> {
        command.process_group(0);
        command
            .stdin(Stdio::null())
            .stdout(File::create(&stdout_path).map_err(|error| error.to_string())?)
            .stderr(File::create(&stderr_path).map_err(|error| error.to_string())?);
        let mut child = command.spawn().map_err(|error| error.to_string())?;
        let deadline = Instant::now() + timeout;
        let status = loop {
            match child.try_wait() {
                Ok(Some(status)) => break status,
                Ok(None) if Instant::now() < deadline => {
                    std::thread::sleep(Duration::from_millis(25))
                }
                Ok(None) => {
                    // Kill Matugen and other descendants before restoring files.
                    unsafe { libc::kill(-(child.id() as i32), libc::SIGKILL) };
                    let _ = child.kill();
                    let _ = child.wait();
                    return Err("Appearance helper timed out".into());
                }
                Err(error) => {
                    let _ = child.kill();
                    let _ = child.wait();
                    return Err(error.to_string());
                }
            }
        };
        if status.success() {
            return Ok(());
        }
        let bytes = fs::read(&stderr_path).unwrap_or_default();
        let bytes = if bytes.is_empty() {
            fs::read(&stdout_path).unwrap_or_default()
        } else {
            bytes
        };
        let text = String::from_utf8_lossy(&bytes);
        let tail = text
            .chars()
            .rev()
            .take(1400)
            .collect::<String>()
            .chars()
            .rev()
            .collect::<String>();
        Err(format!("Appearance helper failed ({status}): {tail}"))
    })();
    let _ = fs::remove_file(stdout_path);
    let _ = fs::remove_file(stderr_path);
    result
}

fn apply_ui(cfg: &mut Value, ui: &Value, catalog: &Value) {
    if let (Some(draft), Some(keys)) = (ui.as_object(), catalog["snapshotKeys"].as_array()) {
        for key in keys.iter().filter_map(Value::as_str) {
            if let Some(value) = draft.get(key).filter(|value| !value.is_null()) {
                set_nested(cfg, key, value.clone());
            }
        }
    }
}

fn target_flags(cfg: &mut Value, targets: &Value, core: bool) {
    if core {
        set_nested(
            cfg,
            "appearance.wallpaperTheming.enableAppsAndShell",
            json!(true),
        );
    }
    for (target, flag) in [("qt", "enableQtApps"), ("terminal", "enableTerminal")] {
        set_nested(
            cfg,
            &format!("appearance.wallpaperTheming.{flag}"),
            json!(targets[target].as_bool().unwrap_or(true)),
        );
    }
}

fn palette_settings(cfg: &mut Value, resolved: &Value) {
    set_nested(cfg, "appearance.palette.type", resolved["scheme"].clone());
    let fixed = ["preset", "custom"].contains(&string_at(resolved, "source"));
    set_nested(
        cfg,
        "appearance.palette.accentColor",
        if fixed {
            resolved["seed"].clone()
        } else {
            json!("")
        },
    );
}

fn active(resolved: &Value, cfg: &Value, catalog: &Value) -> Value {
    let mut value = json!({
        "source": resolved["source"], "mode": resolved["mode"],
        "scheme": resolved["scheme"], "wallpaper": resolved["wallpaper"],
        "preset": resolved["preset"], "seed": resolved["seed"],
        "uiProfile": detect_profile(cfg, catalog),
    });
    if resolved["source"] == "custom" && resolved["customPalette"].is_object() {
        value["customPalette"] = resolved["customPalette"].clone();
    }
    value
}

fn history_entry(
    active: &Value,
    ui: &Value,
    colors: &Value,
    catalog: &Value,
) -> Result<Value, String> {
    let scheme = string_at(active, "scheme");
    let scheme_name = catalog["schemes"]
        .as_array()
        .into_iter()
        .flatten()
        .find(|item| item["id"] == scheme)
        .and_then(|item| item["name"].as_str())
        .unwrap_or(scheme);
    let source = string_at(active, "source");
    let preset_name = catalog["presets"]
        .as_array()
        .into_iter()
        .flatten()
        .find(|item| item["id"] == string_at(active, "preset"))
        .and_then(|item| item["name"].as_str())
        .unwrap_or("Preset");
    let wallpaper_name = Path::new(string_at(active, "wallpaper"))
        .file_stem()
        .and_then(|value| value.to_str())
        .filter(|value| !value.is_empty())
        .unwrap_or("Wallpaper");
    let source_name = match source {
        "preset" => preset_name.to_owned(),
        "hybrid" => format!("{wallpaper_name} + {preset_name}"),
        "custom" => string_at(active, "seed").to_owned(),
        _ => wallpaper_name.to_owned(),
    };
    let mode = string_at(active, "mode");
    let mut title = mode.chars();
    let mode_title = title
        .next()
        .map(|first| first.to_uppercase().collect::<String>() + title.as_str())
        .unwrap_or_default();
    Ok(json!({
        "id": crate::random_id()?, "timestamp": epoch_seconds()? as i64,
        "label": format!("{source_name} · {scheme_name} · {mode_title}"),
        "customLabel": false, "fingerprint": crate::fingerprint(active, ui)?,
        "active": active, "colors": colors, "ui": ui,
    }))
}

fn sync_radius(cfg: &Value, catalog: &Value) -> Result<(), String> {
    let path = xconfig()?.join("hypr/custom/appearance-runtime.lua");
    let old = fs::read_to_string(&path).unwrap_or_default();
    let begin = "-- >>> Appearance Studio: window radius >>>";
    let end = "-- <<< Appearance Studio: window radius <<<";
    let value = radius(cfg, catalog, "window");
    let block = format!("{begin}\nhl.config({{decoration = {{rounding = {value}}}}})\n{end}");
    let updated = if let (Some(start), Some(end_pos)) = (old.find(begin), old.find(end)) {
        if end_pos >= start {
            format!("{}{}{}", &old[..start], block, &old[end_pos + end.len()..])
        } else {
            format!("{}\n\n{}\n", old.trim_end_matches('\n'), block)
        }
    } else {
        format!("{}\n\n{}\n", old.trim_end_matches('\n'), block)
    };
    if updated != old {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|error| error.to_string())?;
        }
        fs::write(&path, updated).map_err(|error| error.to_string())?;
    }
    if env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_some() {
        let mut command = Command::new("hyprctl");
        command.args([
            "repl",
            &format!("hl.config({{decoration = {{rounding = {value}}}}})"),
        ]);
        run_command(command, Duration::from_secs(5))?;
    }
    Ok(())
}

fn runtime_mode(cfg: &Value, catalog: &Value) -> (bool, bool) {
    (
        get_nested(cfg, "appearance.transparency.enable").is_some_and(is_truthy),
        detect_profile(cfg, catalog) == "fluid",
    )
}

fn sync_runtime(cfg: &Value, catalog: &Value) -> Result<(), String> {
    let (glass, fluid) = runtime_mode(cfg, catalog);
    for (helper, mode) in [
        (
            "nyvorel-glass-runtime",
            if glass { "glass" } else { "default" },
        ),
        (
            "nyvorel-fluid-runtime",
            if fluid { "fluid" } else { "default" },
        ),
    ] {
        let path = home()?.join(".local/bin").join(helper);
        if !path.is_file() {
            return Err(format!("Missing runtime helper: {}", path.display()));
        }
        let mut command = Command::new(path);
        command.arg(mode);
        run_command(command, Duration::from_secs(20))?;
    }
    Ok(())
}

fn switchwall(mode: &str, scheme: &str, seed: &str, targets: &Value) -> Result<(), String> {
    let path = nyvorel_dir()?.join("scripts/colors/switchwall.sh");
    if !path.is_file() {
        return Err(format!("Missing switchwall.sh: {}", path.display()));
    }
    let mut command = Command::new(path);
    command.args([
        "--noswitch",
        "--mode",
        mode,
        "--type",
        scheme,
        "--color",
        seed,
    ]);
    command
        .env("NYVOREL_APPEARANCE_STUDIO_MANAGED", "1")
        .env("NYVOREL_APPEARANCE_STUDIO_SKIP_TERMINAL", "1")
        .env(
            "NYVOREL_APPEARANCE_STUDIO_SKIP_GSETTINGS",
            if targets["gtk"].as_bool().unwrap_or(true) {
                "0"
            } else {
                "1"
            },
        );
    run_command(command, Duration::from_secs(90))
}

fn write_text(path: &Path, contents: &str) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    fs::write(path, contents).map_err(|error| error.to_string())
}

fn merge_hybrid(base: &Value, accent: &Value) -> Value {
    let mut merged = accent.clone();
    for role in HYBRID_SURFACE_ROLES {
        if let Some(value) = base.get(*role) {
            merged[*role] = value.clone();
        }
    }
    merged
}

fn run_optional(
    path: PathBuf,
    args: &[&str],
    timeout: Duration,
    envs: &[(&str, &str)],
) -> Result<(), String> {
    if !path.is_file() {
        return Ok(());
    }
    let mut command = Command::new(path);
    command.args(args);
    for (key, value) in envs {
        command.env(key, value);
    }
    run_command(command, timeout)
}

fn post_integrations(targets: &Value, scheme: &str) -> Vec<String> {
    let mut warnings = Vec::new();
    if targets["terminal"].as_bool().unwrap_or(true) {
        if let Ok(root) = nyvorel_dir() {
            if let Err(error) = run_optional(
                root.join("scripts/colors/applycolor.sh"),
                &[],
                Duration::from_secs(20),
                &[
                    ("NYVOREL_APPEARANCE_STUDIO_MANAGED", "1"),
                    ("NYVOREL_APPEARANCE_STUDIO_SKIP_TERMINAL", "0"),
                ],
            ) {
                warnings.push(format!("Terminal theme: {error}"));
            }
        }
    }
    if targets["editors"].as_bool().unwrap_or(true) {
        if let (Ok(root), Ok(files)) = (nyvorel_dir(), all_editor_paths()) {
            if let Ok(before) = capture(&files) {
                if let Err(error) = run_optional(
                    root.join("scripts/colors/code/material-code-set-color.sh"),
                    &[],
                    Duration::from_secs(30),
                    &[],
                ) {
                    let _ = before.restore();
                    warnings.push(format!("Editor accents: {error}"));
                }
            }
        }
    }
    if targets["qt"].as_bool().unwrap_or(true) {
        if let Ok(root) = xconfig() {
            if let Err(error) = run_optional(
                root.join("matugen/templates/kde/kde-material-you-colors-wrapper.sh"),
                &["--scheme-variant", scheme],
                Duration::from_secs(30),
                &[],
            ) {
                warnings.push(format!("Qt/KDE theme: {error}"));
            }
        }
    }
    warnings
}

fn rollback(
    snapshot: &Snapshot,
    gsettings: &Value,
    cfg_before: &Value,
    catalog: &Value,
) -> Result<(), String> {
    snapshot.restore()?;
    restore_gsettings(gsettings);
    sync_runtime_best_effort(cfg_before, catalog);
    let _ = sync_radius(cfg_before, catalog);
    snapshot.restore()
}

fn parse_apply(args: &[String]) -> Result<Value, String> {
    let mut request = json!({"source":"wallpaper", "mode":"dark", "scheme":"auto", "preset":"", "seed":"", "wallpaper":"", "ui":{}});
    let mut index = 1;
    while index < args.len() {
        if args[index] == "--preview" {
            request["preview"] = json!(true);
            index += 1;
            continue;
        }
        if index + 1 >= args.len() {
            return Err(format!("Missing value for {}", args[index]));
        }
        let value = &args[index + 1];
        match args[index].as_str() {
            "--source" => {
                if !["wallpaper", "preset", "custom", "hybrid"].contains(&value.as_str()) {
                    return Err("Invalid source".into());
                }
                request["source"] = json!(value);
            }
            "--mode" => {
                if !["light", "dark", "dim", "oled", "high-contrast"].contains(&value.as_str()) {
                    return Err("Invalid mode".into());
                }
                request["mode"] = json!(value);
            }
            "--scheme" => {
                request["scheme"] = json!(value);
            }
            "--preset" => {
                request["preset"] = json!(value);
            }
            "--seed" => {
                request["seed"] = json!(value);
            }
            "--wallpaper" => {
                request["wallpaper"] = json!(value);
            }
            "--ui-json" => {
                let ui: Value = serde_json::from_str(value)
                    .map_err(|error| format!("Invalid UI draft JSON: {error}"))?;
                if !ui.is_object() {
                    return Err("UI draft must be a JSON object".into());
                }
                request["ui"] = ui;
            }
            other => return Err(format!("Unknown apply option: {other}")),
        }
        index += 2;
    }
    Ok(request)
}

fn video_wallpaper_runtime(wallpaper: &str, best_effort: bool) -> Result<(), String> {
    if wallpaper.is_empty() {
        return Ok(());
    }
    let path = local_path(wallpaper);
    let video = crate::is_video(&path);
    let action = (|| -> Result<(), String> {
        let mut stop = Command::new("pkill");
        stop.args(["-f", "mpvpaper"]);
        let _ = crate::run_bounded(stop, Duration::from_secs(3));
        if !video {
            write_text(
                &video_script()?,
                "#!/usr/bin/env bash\n# No video wallpaper currently needs restoring.\n",
            )?;
            return Ok(());
        }
        if !path.is_file() {
            return Err(format!("Video wallpaper not found: {}", path.display()));
        }
        let monitors_output = Command::new("hyprctl")
            .args(["monitors", "-j"])
            .output()
            .map_err(|error| error.to_string())?;
        if !monitors_output.status.success() {
            return Err("Could not determine Hyprland monitors for video wallpaper".into());
        }
        let monitors: Value =
            serde_json::from_slice(&monitors_output.stdout).map_err(|error| error.to_string())?;
        let names = monitors
            .as_array()
            .ok_or("Invalid Hyprland monitor list")?
            .iter()
            .filter_map(|monitor| monitor["name"].as_str())
            .collect::<Vec<_>>();
        if names.is_empty() {
            return Err("Could not determine Hyprland monitors for video wallpaper".into());
        }
        for name in names {
            Command::new("mpvpaper")
                .args(["-o", VIDEO_OPTS, name])
                .arg(&path)
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn()
                .map_err(|error| error.to_string())?;
            std::thread::sleep(Duration::from_millis(80));
        }
        // This script is only used when the session restarts. Quote every
        // path through shell single-quote escaping so arbitrary filenames work.
        let quoted = format!("'{}'", path.display().to_string().replace('\'', "'\\''"));
        let options = format!("'{}'", VIDEO_OPTS);
        let script = format!("#!/usr/bin/env bash\n# Generated by Appearance Studio.\npkill -f mpvpaper 2>/dev/null || true\nfor monitor in $(hyprctl monitors -j | jq -r '.[] | .name'); do\n    mpvpaper -o {options} \"$monitor\" {quoted} >/dev/null 2>&1 &\n    sleep 0.1\ndone\n");
        let script_path = video_script()?;
        write_text(&script_path, &script)?;
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(script_path, fs::Permissions::from_mode(0o755))
            .map_err(|error| error.to_string())?;
        Ok(())
    })();
    if best_effort {
        Ok(())
    } else {
        action
    }
}

fn persistent_video_frame(wallpaper: &str, source_image: &str) -> Result<String, String> {
    let path = local_path(wallpaper);
    if !crate::is_video(&path) {
        return Ok(source_image.to_owned());
    }
    let source = local_path(source_image);
    if !source.is_file() {
        return Err(format!(
            "Video thumbnail is unavailable: {}",
            source.display()
        ));
    }
    let directory = xconfig()?.join("hypr/custom/scripts/mpvpaper_thumbnails");
    fs::create_dir_all(&directory).map_err(|error| error.to_string())?;
    let hash = sha256_hex(path.display().to_string().as_bytes());
    let stem = path
        .file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or("wallpaper");
    let output = directory.join(format!("{stem}-{}.jpg", &hash[..12]));
    if output == source {
        return Ok(output.display().to_string());
    }
    if output.is_file() && fs::metadata(&output).is_ok_and(|metadata| metadata.len() > 0) {
        return Ok(output.display().to_string());
    }
    let bytes = fs::read(&source).map_err(|error| error.to_string())?;
    if bytes.is_empty() {
        return Err("Video thumbnail is empty".into());
    }
    let temporary = directory.join(format!(".{stem}-{}.tmp", crate::random_id()?));
    let result = (|| -> Result<(), String> {
        fs::write(&temporary, bytes).map_err(|error| error.to_string())?;
        File::open(&temporary)
            .and_then(|file| file.sync_all())
            .map_err(|error| error.to_string())?;
        fs::rename(&temporary, &output).map_err(|error| error.to_string())?;
        File::open(&directory)
            .and_then(|dir| dir.sync_all())
            .map_err(|error| error.to_string())?;
        Ok(())
    })();
    let _ = fs::remove_file(&temporary);
    result?;
    Ok(output.display().to_string())
}

fn apply_core(request_draft: &Value, record_history: bool) -> Result<Value, String> {
    let catalog = catalog()?;
    let cfg_before = read_json(&config_path()?);
    let mut state = load_state(&cfg_before, &catalog)?;
    let targets = state["targets"].clone();
    let previous_wallpaper = string_at(&cfg_before, "background.wallpaperPath").to_owned();
    let previous_palette = get_nested(&cfg_before, "appearance.palette")
        .cloned()
        .unwrap_or(json!({}));
    let resolved = request::resolve(request_draft, &cfg_before, &catalog)?;
    let wallpaper = string_at(&resolved, "wallpaper");
    let source_image = if !string_at(&resolved, "sourceImage").is_empty() {
        string_at(&resolved, "sourceImage").to_owned()
    } else if wallpaper.is_empty() {
        String::new()
    } else if crate::is_video(&local_path(wallpaper)) {
        source_image_for_wallpaper(&local_path(wallpaper), &cfg_before)?
            .display()
            .to_string()
    } else {
        wallpaper.to_owned()
    };
    let source_image = if crate::is_video(&local_path(wallpaper)) {
        persistent_video_frame(wallpaper, &source_image)?
    } else {
        source_image
    };

    let mut cfg = cfg_before.clone();
    apply_ui(&mut cfg, &resolved["ui"], &catalog);
    if !wallpaper.is_empty() {
        set_nested(&mut cfg, "background.wallpaperPath", json!(wallpaper));
    }
    if crate::is_video(&local_path(wallpaper)) {
        set_nested(&mut cfg, "background.thumbnailPath", json!(source_image));
    }
    if targets["shell"].as_bool().unwrap_or(true) {
        palette_settings(&mut cfg, &resolved);
    }
    target_flags(&mut cfg, &targets, true);
    atomic_json_write(&config_path()?, &cfg)?;

    let preserved = capture(&disabled_target_paths(&targets)?)?;
    let base_mode = string_at(&resolved, "baseMode");
    let selected_scheme = string_at(&resolved, "resolvedScheme");
    let seed = string_at(&resolved, "seed");
    if resolved["source"] == "hybrid" {
        let base = &resolved["hybridBase"];
        switchwall(
            base_mode,
            string_at(base, "scheme"),
            string_at(base, "seed"),
            &targets,
        )?;
        let base_colors = read_json(&colors_path()?);
        switchwall(base_mode, selected_scheme, seed, &targets)?;
        let accent_colors = read_json(&colors_path()?);
        if targets["shell"].as_bool().unwrap_or(true) {
            atomic_json_write(&colors_path()?, &merge_hybrid(&base_colors, &accent_colors))?;
        }
    } else {
        switchwall(base_mode, selected_scheme, seed, &targets)?;
        if resolved["source"] == "custom"
            && resolved["customPalette"].is_object()
            && targets["shell"].as_bool().unwrap_or(true)
        {
            let colors = request::generate_palette(&resolved)?;
            atomic_json_write(&colors_path()?, &colors)?;
        }
    }
    if targets["shell"].as_bool().unwrap_or(true)
        && ["oled", "dim", "high-contrast"].contains(&string_at(&resolved, "mode"))
    {
        let colors = read_json(&colors_path()?);
        atomic_json_write(
            &colors_path()?,
            &crate::modes::apply(&colors, string_at(&resolved, "mode")),
        )?;
    }
    preserved.restore()?;

    let mut cfg_after = read_json(&config_path()?);
    apply_ui(&mut cfg_after, &resolved["ui"], &catalog);
    if !wallpaper.is_empty() {
        set_nested(&mut cfg_after, "background.wallpaperPath", json!(wallpaper));
    }
    if crate::is_video(&local_path(wallpaper)) {
        set_nested(
            &mut cfg_after,
            "background.thumbnailPath",
            json!(source_image),
        );
    }
    if targets["shell"].as_bool().unwrap_or(true) {
        palette_settings(&mut cfg_after, &resolved);
    } else {
        set_nested(&mut cfg_after, "appearance.palette", previous_palette);
    }
    target_flags(&mut cfg_after, &targets, true);
    ensure_radius(&mut cfg_after, &catalog);
    atomic_json_write(&config_path()?, &cfg_after)?;
    sync_radius(&cfg_after, &catalog)?;
    sync_runtime(&cfg_after, &catalog)?;
    if !source_image.is_empty() {
        write_text(&wallpaper_txt()?, &format!("{source_image}\n"))?;
    }
    if !wallpaper.is_empty() && wallpaper != previous_wallpaper {
        video_wallpaper_runtime(wallpaper, false)?;
    }
    let active_ui = snapshot(&cfg_after, &catalog);
    let active = active(&resolved, &cfg_after, &catalog);
    state["active"] = active.clone();
    state["activeUi"] = active_ui.clone();
    state["preview"] = Value::Null;
    if record_history {
        let colors = read_json(&colors_path()?);
        let entry = history_entry(&active, &active_ui, &colors, &catalog)?;
        let fp = entry["fingerprint"].clone();
        let mut history = vec![entry];
        for item in state["history"].as_array().into_iter().flatten() {
            let item_fp = item["fingerprint"]
                .as_str()
                .map(str::to_owned)
                .unwrap_or_else(|| {
                    crate::fingerprint(&item["active"], &item["ui"]).unwrap_or_default()
                });
            if json!(item_fp) != fp && history.len() < 20 {
                history.push(item.clone());
            }
        }
        state["history"] = Value::Array(history);
    }
    atomic_json_write(&state_path()?, &state)?;
    let warnings = post_integrations(&targets, selected_scheme);
    let mut notes = Vec::new();
    if resolved["source"] == "hybrid" {
        notes.push("Hybrid preset surfaces are merged into the Quickshell palette; external targets use the wallpaper accent palette.");
    }
    if ["oled", "dim", "high-contrast"].contains(&string_at(&resolved, "mode")) {
        notes.push("OLED, Dim, and High Contrast are Quickshell surface treatments; external targets use the dark Material base.");
    }
    Ok(
        json!({"ok": true, "active": active, "preview": false, "previewTimeout": 0,
        "resolvedScheme": selected_scheme, "warnings": warnings, "notes": notes}),
    )
}

fn apply_committed(request: &Value, record_history: bool) -> Result<Value, String> {
    let catalog = catalog()?;
    let cfg_before = read_json(&config_path()?);
    let state = load_state(&cfg_before, &catalog)?;
    if is_truthy(&state["preview"]) {
        return Err(
            "A preview is active; Keep or Revert it before applying another appearance".into(),
        );
    }
    let paths = transaction_paths()?;
    let snapshot = capture(&paths)?;
    let gsettings = gsettings_snapshot();
    let previous_wallpaper = string_at(&cfg_before, "background.wallpaperPath").to_owned();
    let requested_wallpaper = request["wallpaper"]
        .as_str()
        .filter(|value| !value.is_empty())
        .map(local_path)
        .map(|path| path.display().to_string())
        .unwrap_or_else(|| previous_wallpaper.clone());
    match apply_core(request, record_history) {
        Ok(value) => Ok(value),
        Err(error) => {
            let rollback_result = rollback(&snapshot, &gsettings, &cfg_before, &catalog);
            if !previous_wallpaper.is_empty() && requested_wallpaper != previous_wallpaper {
                let _ = video_wallpaper_runtime(&previous_wallpaper, true);
            }
            match rollback_result {
                Ok(()) => Err(error),
                Err(rollback_error) => {
                    Err(format!("{error}; rollback also failed: {rollback_error}"))
                }
            }
        }
    }
}

fn render_preview(draft: &Value, state: &Value, catalog: &Value) -> Result<Value, String> {
    let mut cfg = read_json(&config_path()?);
    let runtime_before = runtime_mode(&cfg, catalog);
    let resolved = request::resolve(draft, &cfg, catalog)?;
    let targets = &state["targets"];
    apply_ui(&mut cfg, &resolved["ui"], catalog);
    target_flags(&mut cfg, targets, false);
    let wallpaper = string_at(&resolved, "wallpaper");
    if !wallpaper.is_empty() {
        let display = if crate::is_video(&local_path(wallpaper)) {
            string_at(&resolved, "sourceImage")
        } else {
            wallpaper
        };
        set_nested(&mut cfg, "background.wallpaperPath", json!(display));
        if crate::is_video(&local_path(wallpaper)) {
            set_nested(
                &mut cfg,
                "background.thumbnailPath",
                resolved["sourceImage"].clone(),
            );
        }
    }
    if targets["shell"].as_bool().unwrap_or(true) {
        palette_settings(&mut cfg, &resolved);
        let mut colors = if resolved["source"] == "hybrid" {
            let base = &resolved["hybridBase"];
            let base_colors = crate::palette::generate(
                string_at(base, "seed"),
                string_at(base, "scheme"),
                string_at(&resolved, "baseMode"),
            )?;
            let accent_colors = request::generate_palette(&resolved)?;
            merge_hybrid(&base_colors, &accent_colors)
        } else {
            request::generate_palette(&resolved)?
        };
        colors = crate::modes::apply(&colors, string_at(&resolved, "mode"));
        atomic_json_write(&colors_path()?, &colors)?;
    }
    ensure_radius(&mut cfg, catalog);
    atomic_json_write(&config_path()?, &cfg)?;
    if runtime_before != runtime_mode(&cfg, catalog) {
        sync_runtime(&cfg, catalog)?;
    }
    Ok(json!({"active": active(&resolved, &cfg, catalog), "resolved": resolved}))
}

fn launch_watchdog(token: &str, revision: i64) -> Result<(), String> {
    if env::var_os("NYVOREL_APPEARANCE_TEST_NO_WATCHDOG").is_some() {
        return Ok(());
    }
    let binary = env::current_exe().map_err(|error| error.to_string())?;
    let unit = format!(
        "nyvorel-appearance-preview-{token}-{revision}-{}",
        crate::random_id()?
    );
    let args = ["preview-watchdog", "--token", token, "--revision"];
    let mut scheduled = Command::new("systemd-run");
    scheduled
        .args([
            "--user",
            "--collect",
            &format!("--unit={unit}"),
            "--on-active=15s",
        ])
        .arg(&binary)
        .args(args)
        .arg(revision.to_string())
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    if crate::run_bounded(scheduled, Duration::from_secs(4)).unwrap_or(false) {
        return Ok(());
    }
    // No persistent process exists except during the fifteen-second preview.
    Command::new(binary)
        .args(args)
        .arg(revision.to_string())
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|error| format!("Could not schedule preview rollback: {error}"))?;
    Ok(())
}

fn baseline_preserving_globals(state: &Value, preview: &Path) -> Result<Value, String> {
    let mut baseline: Value = serde_json::from_slice(
        &fs::read(preview.join("state-before.json")).map_err(|error| error.to_string())?,
    )
    .map_err(|error| error.to_string())?;
    if !baseline["active"].is_object() {
        return Err("Invalid preview baseline".into());
    }
    for key in ["targets", "favorites", "history"] {
        baseline[key] = state[key].clone();
    }
    baseline["version"] = json!(4);
    baseline["preview"] = Value::Null;
    Ok(baseline)
}

fn apply_preview(draft: &Value) -> Result<Value, String> {
    let catalog = catalog()?;
    let cfg_before = read_json(&config_path()?);
    let mut state = load_state(&cfg_before, &catalog)?;
    let paths = transaction_paths()?;
    let current_files = capture(&paths)?;
    let current_gsettings = gsettings_snapshot();
    let preview = preview_path()?;
    let existing = state["preview"].clone();
    let valid_session = is_truthy(&existing)
        && preview.is_dir()
        && preview.join("manifest.json").is_file()
        && preview.join("state-before.json").is_file();
    let result = (|| -> Result<Value, String> {
        let (token, revision) = if valid_session {
            restore_preview_runtime(&preview, &catalog)?;
            let mut restored = read_json(&config_path()?);
            target_flags(&mut restored, &state["targets"], false);
            atomic_json_write(&config_path()?, &restored)?;
            (
                existing["token"]
                    .as_str()
                    .map(str::to_owned)
                    .unwrap_or(crate::random_id()?),
                existing["revision"].as_i64().unwrap_or(0) + 1,
            )
        } else {
            if preview.exists() {
                fs::remove_dir_all(&preview).map_err(|error| error.to_string())?;
            }
            let mut baseline = state.clone();
            baseline["preview"] = Value::Null;
            Snapshot::create_preview(
                &preview,
                &preview_allowed_paths()?,
                &baseline,
                &current_gsettings,
            )?;
            (crate::random_id()?, 1)
        };
        let now = epoch_seconds()?;
        let started = if valid_session {
            existing["started"].as_i64().unwrap_or(now as i64)
        } else {
            now as i64
        };
        let mut preview_state = json!({
            "token": token, "revision": revision, "started": started,
            "updated": now as i64, "expiresAt": now + 15.0, "timeoutSeconds": 15,
            "candidate": if valid_session { existing["candidate"].clone() } else { Value::Null },
            "request": draft, "resolvedScheme": if valid_session { existing["resolvedScheme"].clone() } else { json!("") },
            "status": "rendering",
        });
        state["preview"] = preview_state.clone();
        atomic_json_write(&state_path()?, &state)?;
        launch_watchdog(&token, revision)?;
        let rendered = render_preview(draft, &state, &catalog)?;
        let now = epoch_seconds()?;
        preview_state["updated"] = json!(now as i64);
        preview_state["expiresAt"] = json!(now + 15.0);
        preview_state["candidate"] = rendered["active"].clone();
        preview_state["resolvedScheme"] = rendered["resolved"]["resolvedScheme"].clone();
        preview_state["status"] = json!("active");
        state["preview"] = preview_state.clone();
        atomic_json_write(&state_path()?, &state)?;
        launch_watchdog(&token, revision)?;
        Ok(
            json!({"ok": true, "active": rendered["active"], "preview": true,
            "previewTimeout": 15, "previewState": preview_state,
            "resolvedScheme": rendered["resolved"]["resolvedScheme"]}),
        )
    })();
    if result.is_err() {
        let _ = rollback(&current_files, &current_gsettings, &cfg_before, &catalog);
        if !valid_session {
            let _ = fs::remove_dir_all(&preview);
        }
    }
    result
}

fn keep_preview() -> Result<Value, String> {
    let catalog = catalog()?;
    let cfg_before = read_json(&config_path()?);
    let state = load_state(&cfg_before, &catalog)?;
    let existing = state["preview"].clone();
    if !is_truthy(&existing) {
        return Ok(json!({"ok": true, "message": "No preview is active"}));
    }
    let request = existing["request"].clone();
    if !request.is_object() {
        return Err("Preview request is missing; revert the preview and try again".into());
    }
    let preview = preview_path()?;
    let current_files = capture(&transaction_paths()?)?;
    let current_gsettings = gsettings_snapshot();
    let result = (|| -> Result<Value, String> {
        let baseline = baseline_preserving_globals(&state, &preview)?;
        restore_preview_runtime(&preview, &catalog)?;
        let mut cfg = read_json(&config_path()?);
        target_flags(&mut cfg, &baseline["targets"], false);
        atomic_json_write(&config_path()?, &cfg)?;
        atomic_json_write(&state_path()?, &baseline)?;
        let mut applied = apply_core(&request, true)?;
        fs::remove_dir_all(&preview).map_err(|error| error.to_string())?;
        applied["keptPreview"] = json!(true);
        Ok(applied)
    })();
    if let Err(error) = result {
        let rollback_result = rollback(&current_files, &current_gsettings, &cfg_before, &catalog);
        let mut restored = read_json(&state_path()?);
        let mut preview_state = if is_truthy(&restored["preview"]) {
            restored["preview"].clone()
        } else {
            existing
        };
        let token = preview_state["token"]
            .as_str()
            .map(str::to_owned)
            .unwrap_or(crate::random_id()?);
        let revision = preview_state["revision"].as_i64().unwrap_or(0) + 1;
        let now = epoch_seconds()?;
        preview_state["token"] = json!(token);
        preview_state["revision"] = json!(revision);
        preview_state["updated"] = json!(now as i64);
        preview_state["expiresAt"] = json!(now + 15.0);
        preview_state["timeoutSeconds"] = json!(15);
        restored["preview"] = preview_state;
        let _ = atomic_json_write(&state_path()?, &restored);
        let _ = launch_watchdog(&token, revision);
        return match rollback_result {
            Ok(()) => Err(error),
            Err(other) => Err(format!("{error}; rollback also failed: {other}")),
        };
    }
    result
}

fn apply_saved(kind: &str, id: &str) -> Result<Value, String> {
    let catalog = catalog()?;
    let state = load_state(&read_json(&config_path()?), &catalog)?;
    if is_truthy(&state["preview"]) {
        return Err("Keep or Revert the preview before restoring a saved appearance".into());
    }
    let entries = if kind == "favorite-apply" {
        &state["favorites"]
    } else {
        &state["history"]
    };
    let entry = entries
        .as_array()
        .into_iter()
        .flatten()
        .find(|entry| entry["id"] == id)
        .ok_or(if kind == "favorite-apply" {
            "Favorite not found"
        } else {
            "History item not found"
        })?;
    let active = &entry["active"];
    let draft = json!({
        "source": active["source"].as_str().unwrap_or("wallpaper"),
        "mode": active["mode"].as_str().unwrap_or("dark"),
        "scheme": active["scheme"].as_str().unwrap_or("auto"),
        "preset": active["preset"].as_str().unwrap_or(""),
        "seed": active["seed"].as_str().unwrap_or(""),
        "wallpaper": active["wallpaper"].as_str().unwrap_or(""),
        "customPalette": active["customPalette"],
        "ui": entry["ui"].as_object().map(|_| entry["ui"].clone()).unwrap_or(json!({})),
    });
    apply_committed(&draft, true)
}

fn ui_profile(id: &str) -> Result<Value, String> {
    let catalog = catalog()?;
    let canonical = catalog["legacyAliases"][id].as_str().unwrap_or(id);
    let profile = catalog["uiProfiles"]
        .as_array()
        .into_iter()
        .flatten()
        .find(|profile| profile["id"] == canonical)
        .ok_or_else(|| format!("Unknown UI profile: {id}"))?;
    let cfg_before = read_json(&config_path()?);
    let paths = transaction_paths()?;
    let files = capture(&paths)?;
    let gsettings = gsettings_snapshot();
    let result = (|| -> Result<Value, String> {
        let mut cfg = cfg_before.clone();
        ensure_radius(&mut cfg, &catalog);
        for (key, value) in profile["patch"]
            .as_object()
            .ok_or("Invalid profile patch")?
        {
            set_nested(&mut cfg, key, value.clone());
        }
        atomic_json_write(&config_path()?, &cfg)?;
        sync_radius(&cfg, &catalog)?;
        sync_runtime(&cfg, &catalog)?;
        let mut state = load_state(&cfg, &catalog)?;
        state["active"]["uiProfile"] = json!(canonical);
        state["activeUi"] = snapshot(&cfg, &catalog);
        atomic_json_write(&state_path()?, &state)?;
        Ok(json!({"ok": true, "uiProfile": canonical}))
    })();
    if let Err(error) = result {
        return match rollback(&files, &gsettings, &cfg_before, &catalog) {
            Ok(()) => Err(error),
            Err(other) => Err(format!("{error}; rollback also failed: {other}")),
        };
    }
    result
}

fn target_enable(name: &str) -> Result<Value, String> {
    let catalog = catalog()?;
    let cfg_before = read_json(&config_path()?);
    let mut state = load_state(&cfg_before, &catalog)?;
    if !state["targets"][name].is_boolean() {
        return Err(format!("Unknown target: {name}"));
    }
    if state["targets"][name] == true {
        return Ok(
            json!({"ok": true, "target": name, "enabled": true, "synchronized": false, "warnings": []}),
        );
    }
    if is_truthy(&state["preview"]) {
        return Err("Keep or Revert the preview before enabling an appearance target".into());
    }
    let status = crate::status()?;
    let active = &status["active"];
    let draft = json!({
        "source": active["source"], "mode": active["mode"], "scheme": active["scheme"],
        "preset": active["preset"], "seed": active["seed"], "wallpaper": active["wallpaper"],
        "customPalette": active["customPalette"], "ui": status["activeUi"],
    });
    let files = capture(&transaction_paths()?)?;
    let gsettings = gsettings_snapshot();
    state["targets"][name] = json!(true);
    let result = (|| -> Result<Value, String> {
        atomic_json_write(&state_path()?, &state)?;
        if name == "qt" || name == "terminal" {
            let mut cfg = read_json(&config_path()?);
            target_flags(&mut cfg, &state["targets"], false);
            atomic_json_write(&config_path()?, &cfg)?;
        }
        let applied = apply_core(&draft, false)?;
        Ok(
            json!({"ok": true, "target": name, "enabled": true, "synchronized": true,
            "warnings": applied["warnings"]}),
        )
    })();
    if let Err(error) = result {
        return match rollback(&files, &gsettings, &cfg_before, &catalog) {
            Ok(()) => Err(error),
            Err(other) => Err(format!("{error}; rollback also failed: {other}")),
        };
    }
    result
}

fn variants(args: &[String]) -> Result<Value, String> {
    let mut wallpaper = "";
    let mut mode = "dark";
    let mut index = 1;
    while index < args.len() {
        if index + 1 >= args.len() {
            return Err(format!("Missing value for {}", args[index]));
        }
        match args[index].as_str() {
            "--wallpaper" => wallpaper = &args[index + 1],
            "--mode" => mode = &args[index + 1],
            other => return Err(format!("Unknown variants option: {other}")),
        }
        index += 2;
    }
    if !["light", "dark", "dim", "oled", "high-contrast"].contains(&mode) {
        return Err(format!("Invalid mode: {mode}"));
    }
    let mut result = crate::variant_palettes(wallpaper, mode)?;
    // This identifies the stable user-facing contract, not the implementation.
    if result["intelligence"]["engine"].is_string() {
        result["intelligence"]["engine"] = json!("semantic-palette-score-v1");
    }
    Ok(result)
}

pub fn execute(args: &[String]) -> Result<Value, String> {
    let command = args.first().map(String::as_str).ok_or("Missing command")?;
    if command == "variants" {
        return variants(args);
    }
    let _lock = crate::MutationLock::acquire()?;
    match command {
        "apply" => {
            let mut draft = parse_apply(args)?;
            let preview = draft["preview"] == true;
            if let Some(object) = draft.as_object_mut() {
                object.remove("preview");
            }
            if preview {
                apply_preview(&draft)
            } else {
                apply_committed(&draft, true)
            }
        }
        "keep-preview" if args.len() == 1 => keep_preview(),
        "ui-profile" if args.len() == 2 => ui_profile(&args[1]),
        "favorite-apply" | "history-apply" if args.len() == 2 => apply_saved(command, &args[1]),
        _ => Err(format!("Invalid {command} command")),
    }
}

pub fn enable_target(name: &str) -> Result<Value, String> {
    let _lock = crate::MutationLock::acquire()?;
    target_enable(name)
}
