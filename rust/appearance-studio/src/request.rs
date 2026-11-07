//! Resolve an Appearance Studio draft without changing the active desktop.

use serde_json::{json, Value};
use std::path::Path;

const ANCHORS: [&str; 4] = ["primary", "secondary", "tertiary", "neutral"];
const NEUTRAL_ROLES: &[&str] = &[
    "background",
    "on_background",
    "surface",
    "on_surface",
    "surface_dim",
    "surface_bright",
    "surface_container_lowest",
    "surface_container_low",
    "surface_container",
    "surface_container_high",
    "surface_container_highest",
    "surface_variant",
    "on_surface_variant",
    "outline",
    "outline_variant",
    "inverse_surface",
    "inverse_on_surface",
    "scrim",
    "shadow",
];

fn custom_hex(value: &str) -> Option<String> {
    let value = value.trim();
    if value.len() == 7
        && value.starts_with('#')
        && value[1..].bytes().all(|b| b.is_ascii_hexdigit())
    {
        Some(value.to_uppercase())
    } else {
        None
    }
}

pub fn custom_anchors(request: &Value) -> Option<Value> {
    if request["customPalette"].is_object() {
        let mut candidate = json!({});
        let mut complete = true;
        for role in ANCHORS {
            if let Some(value) = custom_hex(request["customPalette"][role].as_str().unwrap_or("")) {
                candidate[role] = json!(value);
            } else {
                complete = false;
                break;
            }
        }
        if complete {
            return Some(candidate);
        }
    }
    let raw = request["seed"].as_str()?.strip_prefix("ii4:")?;
    let parts = raw.split('|').collect::<Vec<_>>();
    if parts.len() != 4 {
        return None;
    }
    let mut candidate = json!({});
    for (role, raw) in ANCHORS.into_iter().zip(parts) {
        candidate[role] = json!(custom_hex(raw)?);
    }
    Some(candidate)
}

fn preset<'a>(catalog: &'a Value, id: &str) -> Result<&'a Value, String> {
    catalog["presets"]
        .as_array()
        .into_iter()
        .flatten()
        .find(|item| item["id"] == id)
        .ok_or_else(|| format!("Unknown preset: {id}"))
}

pub fn resolve(request: &Value, cfg: &Value, catalog: &Value) -> Result<Value, String> {
    let mut source = request["source"]
        .as_str()
        .filter(|value| !value.is_empty())
        .unwrap_or("wallpaper");
    let mode = request["mode"]
        .as_str()
        .filter(|value| !value.is_empty())
        .unwrap_or("dark");
    let requested_scheme = request["scheme"]
        .as_str()
        .filter(|value| !value.is_empty())
        .unwrap_or("auto");
    let mut selected_preset = request["preset"].as_str().unwrap_or("").to_owned();
    let mut raw_seed = request["seed"].as_str().unwrap_or("").to_owned();
    let anchors = custom_anchors(request);
    if let Some(anchors) = &anchors {
        raw_seed = anchors["primary"].as_str().unwrap_or("").to_owned();
    }
    let wallpaper = request["wallpaper"]
        .as_str()
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| crate::string_at(cfg, "background.wallpaperPath"));
    let wallpaper = if wallpaper.is_empty() {
        String::new()
    } else {
        crate::local_path(wallpaper).display().to_string()
    };
    let ui = request["ui"]
        .as_object()
        .map(|_| request["ui"].clone())
        .unwrap_or_else(|| json!({}));
    let mut source_image = String::new();
    let mut hybrid_base = json!({});
    let mut intelligence = Value::Null;
    let base_mode = if mode == "light" { "light" } else { "dark" };
    let (seed, resolved_scheme) = match source {
        "preset" => {
            let chosen = preset(
                catalog,
                if selected_preset.is_empty() {
                    "midnight"
                } else {
                    &selected_preset
                },
            )?;
            selected_preset = chosen["id"].as_str().unwrap_or("").to_owned();
            (
                chosen["seed"].as_str().unwrap_or("").to_owned(),
                if requested_scheme == "auto" {
                    chosen["scheme"].as_str().unwrap_or("").to_owned()
                } else {
                    requested_scheme.to_owned()
                },
            )
        }
        "custom" => {
            let seed = if raw_seed.starts_with('#') {
                raw_seed
            } else {
                format!("#{raw_seed}")
            };
            if custom_hex(&seed).is_none() {
                return Err("Custom color must be a 6-digit hex color".into());
            }
            (
                seed,
                if requested_scheme == "auto" {
                    "scheme-tonal-spot".to_owned()
                } else {
                    requested_scheme.to_owned()
                },
            )
        }
        "hybrid" | "wallpaper" => {
            if wallpaper.is_empty() {
                return Err("No wallpaper is configured".into());
            }
            let image = crate::source_image_for_wallpaper(Path::new(&wallpaper), cfg)?;
            source_image = image.display().to_string();
            let matrix = crate::intelligence::matrix(&image, base_mode, mode, &catalog["schemes"])?;
            let selected = if requested_scheme == "auto" {
                &matrix["best"]
            } else {
                matrix["evaluations"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .find(|entry| entry["scheme"] == requested_scheme)
                    .ok_or_else(|| format!("No smart palette candidate for {requested_scheme}"))?
            };
            intelligence = json!({
                "seed": selected["seed"], "scheme": selected["scheme"], "score": selected["score"],
                "metrics": selected["metrics"], "reason": selected["reason"],
                "profile": matrix["profile"], "candidateSeeds": matrix["seeds"],
                "engine": "semantic-palette-score-rust-v2",
            });
            if source == "hybrid" {
                let chosen = preset(
                    catalog,
                    if selected_preset.is_empty() {
                        "midnight"
                    } else {
                        &selected_preset
                    },
                )?;
                hybrid_base = chosen.clone();
                selected_preset = chosen["id"].as_str().unwrap_or("").to_owned();
            }
            (
                selected["seed"].as_str().unwrap_or("").to_owned(),
                selected["scheme"].as_str().unwrap_or("").to_owned(),
            )
        }
        _ => {
            source = "wallpaper";
            return resolve(
                &json!({"source": source, "mode": mode, "scheme": requested_scheme,
                "preset": selected_preset, "seed": raw_seed, "wallpaper": wallpaper, "ui": ui}),
                cfg,
                catalog,
            );
        }
    };
    if !catalog["schemes"]
        .as_array()
        .into_iter()
        .flatten()
        .any(|item| item["id"] == resolved_scheme && resolved_scheme != "auto")
    {
        return Err(format!("Unsupported Material scheme: {resolved_scheme}"));
    }
    let mut resolved = json!({
        "source": source,
        "mode": mode,
        "baseMode": base_mode,
        "scheme": requested_scheme,
        "resolvedScheme": resolved_scheme,
        "preset": selected_preset,
        "seed": seed.to_lowercase(),
        "wallpaper": wallpaper,
        "sourceImage": source_image,
        "ui": ui,
        "hybridBase": hybrid_base,
        "intelligence": intelligence,
    });
    if let Some(anchors) = anchors {
        resolved["customPalette"] = anchors;
    }
    Ok(resolved)
}

pub fn generate_palette(resolved: &Value) -> Result<Value, String> {
    let seed = resolved["seed"].as_str().ok_or("Missing resolved seed")?;
    let scheme = resolved["resolvedScheme"]
        .as_str()
        .ok_or("Missing resolved scheme")?;
    let mode = resolved["baseMode"]
        .as_str()
        .ok_or("Missing resolved base mode")?;
    let Some(anchors) = resolved
        .get("customPalette")
        .filter(|value| value.is_object())
    else {
        return crate::palette::generate(seed, scheme, mode);
    };
    let primary =
        crate::palette::generate(anchors["primary"].as_str().unwrap_or(seed), scheme, mode)?;
    let secondary =
        crate::palette::generate(anchors["secondary"].as_str().unwrap_or(seed), scheme, mode)?;
    let tertiary =
        crate::palette::generate(anchors["tertiary"].as_str().unwrap_or(seed), scheme, mode)?;
    let neutral =
        crate::palette::generate(anchors["neutral"].as_str().unwrap_or(seed), scheme, mode)?;
    let mut result = primary.clone();
    for (source, target) in [(&secondary, "secondary"), (&tertiary, "tertiary")] {
        for (from, to) in [
            ("primary".to_owned(), target.to_owned()),
            ("on_primary".to_owned(), format!("on_{target}")),
            (
                "primary_container".to_owned(),
                format!("{target}_container"),
            ),
            (
                "on_primary_container".to_owned(),
                format!("on_{target}_container"),
            ),
            ("primary_fixed".to_owned(), format!("{target}_fixed")),
            (
                "primary_fixed_dim".to_owned(),
                format!("{target}_fixed_dim"),
            ),
            ("on_primary_fixed".to_owned(), format!("on_{target}_fixed")),
            (
                "on_primary_fixed_variant".to_owned(),
                format!("on_{target}_fixed_variant"),
            ),
        ] {
            if let Some(value) = source.get(&from) {
                result[&to] = value.clone();
            }
        }
    }
    for role in NEUTRAL_ROLES {
        if let Some(value) = neutral.get(*role) {
            result[*role] = value.clone();
        }
    }
    result["surface_tint"] = result["primary"].clone();
    Ok(result)
}
