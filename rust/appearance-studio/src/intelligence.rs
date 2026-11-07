//! Pure perceptual scoring for wallpaper-derived appearance candidates.

use regex::Regex;
use serde_json::{json, Value};
use std::env;
use std::fs;
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant, UNIX_EPOCH};

fn rgb(value: &str) -> Result<[f64; 3], String> {
    let raw = value.strip_prefix('#').ok_or("Invalid color")?;
    if raw.len() != 6 || !raw.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err(format!("Invalid color: {value}"));
    }
    Ok([
        u8::from_str_radix(&raw[0..2], 16).map_err(|error| error.to_string())? as f64 / 255.0,
        u8::from_str_radix(&raw[2..4], 16).map_err(|error| error.to_string())? as f64 / 255.0,
        u8::from_str_radix(&raw[4..6], 16).map_err(|error| error.to_string())? as f64 / 255.0,
    ])
}

fn linear(value: f64) -> f64 {
    if value <= 0.04045 {
        value / 12.92
    } else {
        ((value + 0.055) / 1.055).powf(2.4)
    }
}

fn srgb(value: f64) -> f64 {
    let value = value.clamp(0.0, 1.0);
    if value <= 0.0031308 {
        12.92 * value
    } else {
        1.055 * value.powf(1.0 / 2.4) - 0.055
    }
}

fn rgb_hex(channels: [f64; 3]) -> String {
    format!(
        "#{:02x}{:02x}{:02x}",
        (channels[0].clamp(0.0, 1.0) * 255.0).round_ties_even() as u8,
        (channels[1].clamp(0.0, 1.0) * 255.0).round_ties_even() as u8,
        (channels[2].clamp(0.0, 1.0) * 255.0).round_ties_even() as u8
    )
}

fn oklab(value: &str) -> Result<[f64; 3], String> {
    let [r, g, b] = rgb(value)?.map(linear);
    let l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b).cbrt();
    let m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b).cbrt();
    let s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b).cbrt();
    Ok([
        0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
        1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
        0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
    ])
}

fn distance(a: &str, b: &str) -> Result<f64, String> {
    let a = oklab(a)?;
    let b = oklab(b)?;
    Ok(((a[0] - b[0]).powi(2) + (a[1] - b[1]).powi(2) + (a[2] - b[2]).powi(2)).sqrt())
}

fn ab_distance(a: &str, b: &str) -> Result<f64, String> {
    let a = oklab(a)?;
    let b = oklab(b)?;
    Ok((a[1] - b[1]).hypot(a[2] - b[2]))
}

fn chroma(value: &str) -> Result<f64, String> {
    let lab = oklab(value)?;
    Ok(lab[1].hypot(lab[2]))
}

fn luminance(value: &str) -> Result<f64, String> {
    let [r, g, b] = rgb(value)?.map(linear);
    Ok(0.2126 * r + 0.7152 * g + 0.0722 * b)
}

fn contrast(a: &str, b: &str) -> Result<f64, String> {
    let (a, b) = (luminance(a)?, luminance(b)?);
    Ok((a.max(b) + 0.05) / (a.min(b) + 0.05))
}

fn clamp(value: f64) -> f64 {
    value.clamp(0.0, 1.0)
}

fn role<'a>(palette: &'a Value, names: &[&str]) -> &'a str {
    for name in names {
        if let Some(value) = palette[*name].as_str() {
            if rgb(value).is_ok() {
                return value;
            }
        }
    }
    ""
}

fn histogram(path: &Path) -> Result<String, String> {
    let mut child = ["magick", "convert"]
        .into_iter()
        .find_map(|program| {
            match Command::new(program)
                .args([
                    path.as_os_str(),
                    "-auto-orient".as_ref(),
                    "-resize".as_ref(),
                    "192x192".as_ref(),
                    "-colors".as_ref(),
                    "32".as_ref(),
                    "-format".as_ref(),
                    "%c".as_ref(),
                    "histogram:info:-".as_ref(),
                ])
                .stdin(Stdio::null())
                .stdout(Stdio::piped())
                .stderr(Stdio::piped())
                .spawn()
            {
                Ok(child) => Some(Ok(child)),
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => None,
                Err(error) => Some(Err(format!("Could not start {program}: {error}"))),
            }
        })
        .ok_or("ImageMagick magick/convert is unavailable")??;
    let deadline = Instant::now() + Duration::from_secs(20);
    loop {
        match child.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(20)),
            Ok(None) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err("Wallpaper profiling timed out".into());
            }
            Err(error) => return Err(format!("Could not wait for ImageMagick: {error}")),
        }
    }
    let output = child
        .wait_with_output()
        .map_err(|error| error.to_string())?;
    if !output.status.success() {
        return Err(format!(
            "ImageMagick failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    String::from_utf8(output.stdout).map_err(|error| error.to_string())
}

struct HistogramRow {
    color: String,
    count: u64,
    lightness: f64,
    chroma: f64,
    luminance: f64,
}

pub fn profile(path: &Path) -> Result<Value, String> {
    if !path.is_file() {
        return Err(format!("Wallpaper not found: {}", path.display()));
    }
    let output = histogram(path)?;
    let pattern = Regex::new(r"(?m)^\s*(\d+):.*?#([0-9A-Fa-f]{6})(?:[0-9A-Fa-f]{2})?\b")
        .map_err(|error| error.to_string())?;
    let mut rows = Vec::new();
    let mut total = 0_u64;
    for capture in pattern.captures_iter(&output) {
        let count = capture[1]
            .parse::<u64>()
            .map_err(|error| error.to_string())?;
        let color = format!("#{}", capture[2].to_lowercase());
        let lab = oklab(&color)?;
        let luminance = luminance(&color)?;
        total += count;
        rows.push(HistogramRow {
            color,
            count,
            lightness: lab[0],
            chroma: lab[1].hypot(lab[2]),
            luminance,
        });
    }
    if rows.is_empty() || total == 0 {
        return Err("ImageMagick returned no usable wallpaper colors".into());
    }
    rows.sort_by_key(|row| std::cmp::Reverse(row.count));
    let mut linear_mean = [0.0; 3];
    let mut mean_luminance = 0.0;
    let mut mean_chroma = 0.0;
    let mut dark = 0_u64;
    let mut bright = 0_u64;
    for row in &rows {
        let weight = row.count as f64 / total as f64;
        let channels = rgb(&row.color)?;
        for index in 0..3 {
            linear_mean[index] += linear(channels[index]) * weight;
        }
        mean_luminance += row.luminance * weight;
        mean_chroma += row.chroma * weight;
        if row.luminance < 0.18 {
            dark += row.count;
        }
        if row.luminance > 0.72 {
            bright += row.count;
        }
    }
    let environment = rgb_hex(linear_mean.map(srgb));
    let max_count = rows[0].count;
    let mut ranked = Vec::new();
    for row in &rows {
        let l = row.lightness;
        let c = row.chroma;
        if !(0.24..=0.90).contains(&l) || c < 0.025 {
            continue;
        }
        let population = (row.count as f64).ln_1p() / (max_count as f64).ln_1p();
        let chroma_score = clamp(c / 0.20);
        let separation = clamp(distance(&row.color, &environment)? / 0.32);
        let lightness_quality = clamp(1.0 - (l - 0.64).abs() / 0.44);
        let highlight_penalty = clamp((l - 0.82) / 0.10);
        let shadow_penalty = clamp((0.30 - l) / 0.10);
        let score = 0.34 * chroma_score
            + 0.23 * separation
            + 0.20 * population
            + 0.15 * lightness_quality
            + 0.08 * (1.0 - (0.55 - row.luminance).abs())
            - 0.22 * highlight_penalty
            - 0.14 * shadow_penalty;
        ranked.push((score, row));
    }
    ranked.sort_by(|a, b| b.0.total_cmp(&a.0));
    let mut accents: Vec<&HistogramRow> = Vec::new();
    let mut accent_json = Vec::new();
    for (score, row) in ranked {
        if accents
            .iter()
            .all(|old| distance(&row.color, &old.color).is_ok_and(|value| value >= 0.055))
        {
            accents.push(row);
            accent_json.push(json!({"hex": row.color, "score": score, "population": row.count as f64 / total as f64, "L": row.lightness, "C": row.chroma}));
        }
        if accents.len() >= 5 {
            break;
        }
    }
    if accent_json.is_empty() {
        let lab = oklab(&environment)?;
        accent_json.push(json!({"hex": environment, "score": 0.0, "population": 1.0, "L": lab[0], "C": lab[1].hypot(lab[2])}));
    }
    let representative: Vec<Value> = rows
        .iter()
        .take(12)
        .map(|row| {
            json!({
                "hex": row.color,
                "population": row.count as f64 / total as f64,
                "L": row.lightness,
                "C": row.chroma,
            })
        })
        .collect();
    Ok(json!({
        "ok": true,
        "image": path.display().to_string(),
        "environment": environment,
        "meanLuminance": mean_luminance,
        "darkFraction": dark as f64 / total as f64,
        "brightFraction": bright as f64 / total as f64,
        "colorfulness": clamp(mean_chroma / 0.16),
        "colors": representative,
        "accentCandidates": accent_json,
    }))
}

pub fn score(profile: &Value, palette: &Value, seed: &str) -> Result<Value, String> {
    let primary = role(palette, &["primary"]);
    let secondary = role(palette, &["secondary"]);
    let tertiary = role(palette, &["tertiary"]);
    let surface = role(palette, &["surface_container", "surface", "background"]);
    let on_surface = role(palette, &["on_surface", "on_background"]);
    if primary.is_empty() || surface.is_empty() || on_surface.is_empty() {
        return Err("Generated palette lacks roles required for scoring".into());
    }
    let mut wallpaper_accents: Vec<String> = profile["accentCandidates"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|entry| entry["hex"].as_str())
        .filter(|value| rgb(value).is_ok())
        .map(str::to_lowercase)
        .collect();
    if wallpaper_accents.is_empty() {
        wallpaper_accents.push(seed.to_owned());
    }
    let environment = profile["environment"]
        .as_str()
        .filter(|value| rgb(value).is_ok())
        .unwrap_or(seed);
    let harmony_distance = wallpaper_accents
        .iter()
        .map(|candidate| distance(primary, candidate))
        .collect::<Result<Vec<_>, _>>()?
        .into_iter()
        .fold(f64::INFINITY, f64::min);
    let wallpaper_harmony = 1.0 - clamp(harmony_distance / 0.30);
    let surface_harmony = 1.0 - clamp(ab_distance(surface, environment)? / 0.15);

    let mut semantic_pairs = vec![(on_surface, surface)];
    for (on_name, base) in [
        ("on_primary", primary),
        ("on_secondary", secondary),
        ("on_tertiary", tertiary),
    ] {
        let on = role(palette, &[on_name]);
        if !on.is_empty() && !base.is_empty() {
            semantic_pairs.push((on, base));
        }
    }
    let readability = semantic_pairs
        .iter()
        .map(|(fg, bg)| contrast(fg, bg).map(|ratio| clamp((ratio - 3.0) / 4.0)))
        .collect::<Result<Vec<_>, _>>()?
        .iter()
        .sum::<f64>()
        / semantic_pairs.len() as f64;
    let accent_contrast = clamp((contrast(primary, surface)? - 1.25) / 3.75);
    let accent_separation = clamp(distance(primary, surface)? / 0.32);
    let accents: Vec<&str> = [primary, secondary, tertiary]
        .into_iter()
        .filter(|value| !value.is_empty())
        .collect();
    let diversity = if accents.len() >= 2 {
        let mut distances = Vec::new();
        for i in 0..accents.len() {
            for j in i + 1..accents.len() {
                distances.push(clamp(distance(accents[i], accents[j])? / 0.18));
            }
        }
        distances.iter().sum::<f64>() / distances.len() as f64
    } else {
        0.5
    };
    let surface_comfort = 1.0 - clamp(chroma(surface)? / 0.13);
    let wallpaper_colorfulness = clamp(profile["colorfulness"].as_f64().unwrap_or(0.5));
    let palette_chroma = accents
        .iter()
        .map(|color| chroma(color))
        .collect::<Result<Vec<_>, _>>()?
        .iter()
        .sum::<f64>()
        / accents.len().max(1) as f64;
    let target_chroma = 0.045 + 0.125 * wallpaper_colorfulness;
    let chroma_match = 1.0 - clamp((palette_chroma - target_chroma).abs() / 0.15);
    let seed_affinity = 1.0 - clamp(distance(primary, seed)? / 0.30);
    let metrics = json!({
        "wallpaperHarmony": wallpaper_harmony,
        "surfaceHarmony": surface_harmony,
        "readability": readability,
        "accentContrast": accent_contrast,
        "accentSeparation": accent_separation,
        "diversity": diversity,
        "surfaceComfort": surface_comfort,
        "chromaMatch": chroma_match,
        "seedAffinity": seed_affinity,
    });
    let total = 0.23 * wallpaper_harmony
        + 0.12 * surface_harmony
        + 0.20 * readability
        + 0.10 * accent_contrast
        + 0.11 * accent_separation
        + 0.06 * diversity
        + 0.08 * surface_comfort
        + 0.06 * chroma_match
        + 0.04 * seed_affinity;
    let mut reasons = [
        (wallpaper_harmony, "wallpaper harmony"),
        (surface_harmony, "surface harmony"),
        (readability, "readability"),
        (accent_contrast, "accent contrast"),
        (accent_separation, "accent separation"),
        (diversity, "color diversity"),
        (surface_comfort, "surface comfort"),
        (chroma_match, "balanced chroma"),
    ];
    reasons.sort_by(|a, b| b.0.total_cmp(&a.0).then_with(|| b.1.cmp(a.1)));
    let reason = reasons[..3]
        .iter()
        .map(|(_, label)| *label)
        .collect::<Vec<_>>()
        .join(" · ");
    Ok(json!({"score": total, "metrics": metrics, "reason": reason}))
}

pub fn matrix(
    path: &Path,
    base_mode: &str,
    display_mode: &str,
    schemes: &Value,
) -> Result<Value, String> {
    let path = path
        .canonicalize()
        .map_err(|error| format!("Wallpaper not found: {error}"))?;
    let metadata = fs::metadata(&path).map_err(|error| error.to_string())?;
    let mtime = metadata
        .modified()
        .map_err(|error| error.to_string())?
        .duration_since(UNIX_EPOCH)
        .map_err(|error| error.to_string())?
        .as_nanos();
    let seed_limit = env::var("NYVOREL_APPEARANCE_SMART_SEEDS")
        .ok()
        .and_then(|value| value.parse::<usize>().ok())
        .unwrap_or(3)
        .clamp(1, 5);
    let cache_key = format!(
        "rust-2|{}|{}|{mtime}|{base_mode}|{display_mode}|{seed_limit}",
        path.display(),
        metadata.len()
    );
    let cache = crate::xdg_path("XDG_CACHE_HOME", ".cache")?
        .join("nyvorel-appearance-studio/intelligence-rust")
        .join(format!("{}.json", crate::sha256_hex(cache_key.as_bytes())));
    let cached = crate::read_json(&cache);
    if cached["version"] == "rust-2"
        && cached["evaluations"]
            .as_array()
            .is_some_and(|array| !array.is_empty())
        && cached["best"].is_object()
    {
        return Ok(cached);
    }
    let profile = profile(&path)?;
    let mut seeds = Vec::<String>::new();
    for value in profile["accentCandidates"].as_array().into_iter().flatten() {
        let Some(color) = value["hex"].as_str() else {
            continue;
        };
        if rgb(color).is_err() || seeds.contains(&color.to_lowercase()) {
            continue;
        }
        if seeds
            .iter()
            .all(|previous| distance(color, previous).is_ok_and(|distance| distance >= 0.045))
        {
            seeds.push(color.to_lowercase());
        }
        if seeds.len() >= seed_limit {
            break;
        }
    }
    if seeds.is_empty() {
        seeds.push(
            profile["environment"]
                .as_str()
                .ok_or("Wallpaper profile lacks a source color")?
                .to_owned(),
        );
    }
    let mut evaluations = Vec::<Value>::new();
    let mut errors = Vec::<String>::new();
    for seed in &seeds {
        for scheme in schemes.as_array().into_iter().flatten() {
            let Some(id) = scheme["id"].as_str() else {
                continue;
            };
            if id == "auto" {
                continue;
            }
            match crate::palette::generate(seed, id, base_mode) {
                Ok(palette) => {
                    let visible = crate::modes::apply(&palette, display_mode);
                    match score(&profile, &visible, seed) {
                        Ok(scored) => evaluations.push(json!({
                            "seed": seed,
                            "scheme": id,
                            "score": scored["score"],
                            "metrics": scored["metrics"],
                            "reason": scored["reason"],
                            "palette": palette,
                            "visiblePalette": visible,
                        })),
                        Err(error) => errors.push(format!("{seed}/{id}: {error}")),
                    }
                }
                Err(error) => errors.push(format!("{seed}/{id}: {error}")),
            }
        }
    }
    if evaluations.is_empty() {
        return Err(format!(
            "Appearance intelligence could not generate any candidate palette. {}",
            errors
                .iter()
                .take(3)
                .cloned()
                .collect::<Vec<_>>()
                .join(" | ")
        ));
    }
    evaluations.sort_by(|a, b| {
        b["score"]
            .as_f64()
            .unwrap_or(f64::NEG_INFINITY)
            .total_cmp(&a["score"].as_f64().unwrap_or(f64::NEG_INFINITY))
    });
    let best = &evaluations[0];
    let result = json!({
        "version": "rust-2",
        "image": path.display().to_string(),
        "baseMode": base_mode,
        "displayMode": display_mode,
        "profile": profile,
        "seeds": seeds,
        "best": {
            "seed": best["seed"], "scheme": best["scheme"], "score": best["score"],
            "metrics": best["metrics"], "reason": best["reason"],
        },
        "evaluations": evaluations,
        "errors": errors.iter().take(8).collect::<Vec<_>>(),
    });
    let _ = crate::atomic_json_write(&cache, &result);
    Ok(result)
}
