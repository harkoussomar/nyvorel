//! Compatibility output for the shared theme pipeline's SCSS palette.
//! Appearance Studio only passes a resolved seed color; wallpaper extraction is
//! handled before this command. This process exits after writing its output.

use material_colors::{
    color::Argb,
    dynamic_color::{DynamicScheme, Variant},
    hct::Hct,
};
use serde_json::Value;
use std::{
    fs,
    path::{Path, PathBuf},
    str::FromStr,
};

struct Options {
    seed: Argb,
    dark: bool,
    variant: Variant,
    termscheme: Option<String>,
    harmony: f64,
    threshold: f64,
    foreground_boost: f64,
    blend_background_foreground: bool,
    cache: Option<PathBuf>,
    image_source: bool,
}

fn options(args: &[String]) -> Result<Options, String> {
    let mut seed = None;
    let mut dark = true;
    let mut variant = Variant::Vibrant;
    let mut termscheme = None;
    let mut harmony = 0.8;
    let mut threshold = 100.0;
    let mut foreground_boost = 0.35;
    let mut blend_background_foreground = false;
    let mut image_path = None;
    let mut cache = None;
    let mut image_size = 128;
    let mut smart = false;
    let mut index = 0;
    while index < args.len() {
        let flag = args[index].as_str();
        if flag == "--blend_bg_fg" {
            blend_background_foreground = true;
            index += 1;
            continue;
        }
        if flag == "--smart" {
            smart = true;
            index += 1;
            continue;
        }
        let value = args
            .get(index + 1)
            .ok_or_else(|| format!("{flag} needs a value"))?;
        match flag {
            "--color" => seed = Some(Argb::from_str(value).map_err(|_| "Invalid seed color")?),
            "--mode" => {
                dark = match value.as_str() {
                    "dark" => true,
                    "light" => false,
                    _ => return Err("Invalid color mode".into()),
                }
            }
            "--scheme" => {
                variant = match value.as_str() {
                    "scheme-content" => Variant::Content,
                    "scheme-expressive" => Variant::Expressive,
                    "scheme-fidelity" => Variant::Fidelity,
                    "scheme-fruit-salad" => Variant::FruitSalad,
                    "scheme-monochrome" => Variant::Monochrome,
                    "scheme-neutral" => Variant::Neutral,
                    "scheme-rainbow" => Variant::Rainbow,
                    "scheme-tonal-spot" => Variant::TonalSpot,
                    "scheme-vibrant" => Variant::Vibrant,
                    _ => Variant::TonalSpot,
                }
            }
            "--termscheme" => termscheme = Some(value.clone()),
            "--harmony" => harmony = parse_number(flag, value)?,
            "--harmonize_threshold" => threshold = parse_number(flag, value)?,
            "--term_fg_boost" => foreground_boost = parse_number(flag, value)?,
            // The old helper only writes the cache when reading --path.
            "--cache" => cache = Some(PathBuf::from(value)),
            "--path" => image_path = Some(PathBuf::from(value)),
            "--size" => {
                image_size = value
                    .parse::<u32>()
                    .map_err(|_| "Invalid image sample size")?
            }
            _ => return Err(format!("Unknown SCSS option: {flag}")),
        }
        index += 2;
    }
    let image_source = image_path.is_some();
    if let Some(path) = image_path {
        seed = Some(crate::color_image::source_color(&path, image_size)?);
    }
    let seed = seed.ok_or("Missing seed color or image path")?;
    if smart && Hct::new(seed).get_chroma() < 20.0 {
        variant = Variant::Neutral;
    }
    Ok(Options {
        seed,
        dark,
        variant,
        termscheme,
        harmony,
        threshold,
        foreground_boost,
        blend_background_foreground,
        cache,
        image_source,
    })
}

fn parse_number(name: &str, value: &str) -> Result<f64, String> {
    let number = value
        .parse::<f64>()
        .map_err(|_| format!("Invalid {name}: {value}"))?;
    if !number.is_finite() {
        return Err(format!("Invalid {name}: {value}"));
    }
    Ok(number)
}

fn hex(color: Argb) -> String {
    format!("#{:02X}{:02X}{:02X}", color.red, color.green, color.blue)
}

fn row(output: &mut String, name: &str, color: Argb) {
    output.push_str(&format!("${name}: {};\n", hex(color)));
}

fn harmonize(design: Argb, source: Argb, harmony: f64, threshold: f64) -> Argb {
    let from = Hct::new(design);
    let to = Hct::new(source);
    let difference = 180.0 - ((from.get_hue() - to.get_hue()).abs() - 180.0).abs();
    let rotation = (difference * harmony).min(threshold);
    let clockwise = (to.get_hue() - from.get_hue()).rem_euclid(360.0) <= 180.0;
    let direction = if clockwise { 1.0 } else { -1.0 };
    Hct::from(
        (from.get_hue() + rotation * direction).rem_euclid(360.0),
        from.get_chroma(),
        from.get_tone(),
    )
    .into()
}

fn boost(color: Argb, chroma: f64, tone: f64) -> Argb {
    let hct = Hct::new(color);
    Hct::from(
        hct.get_hue(),
        hct.get_chroma() * chroma,
        hct.get_tone() * tone,
    )
    .into()
}

pub fn render(args: &[String]) -> Result<String, String> {
    let options = options(args)?;
    let scheme = DynamicScheme::by_variant(options.seed, &options.variant, options.dark, Some(0.0));
    let mut output = format!(
        "$darkmode: {};\n$transparent: False;\n",
        if options.dark { "True" } else { "False" }
    );
    macro_rules! role {
        ($name:literal, $method:ident) => {
            row(&mut output, $name, scheme.$method());
        };
    }
    role!("primary_paletteKeyColor", primary_palette_key_color);
    role!("secondary_paletteKeyColor", secondary_palette_key_color);
    role!("tertiary_paletteKeyColor", tertiary_palette_key_color);
    role!("neutral_paletteKeyColor", neutral_palette_key_color);
    // The upstream convenience method returns the neutral palette here.
    row(
        &mut output,
        "neutral_variant_paletteKeyColor",
        material_colors::dynamic_color::MaterialDynamicColors::neutral_variant_palette_key_color()
            .get_argb(&scheme),
    );
    role!("background", background);
    role!("onBackground", on_background);
    role!("surface", surface);
    role!("surfaceDim", surface_dim);
    role!("surfaceBright", surface_bright);
    role!("surfaceContainerLowest", surface_container_lowest);
    role!("surfaceContainerLow", surface_container_low);
    role!("surfaceContainer", surface_container);
    role!("surfaceContainerHigh", surface_container_high);
    role!("surfaceContainerHighest", surface_container_highest);
    role!("onSurface", on_surface);
    role!("surfaceVariant", surface_variant);
    role!("onSurfaceVariant", on_surface_variant);
    role!("inverseSurface", inverse_surface);
    role!("inverseOnSurface", inverse_on_surface);
    role!("outline", outline);
    role!("outlineVariant", outline_variant);
    role!("shadow", shadow);
    role!("scrim", scrim);
    role!("surfaceTint", surface_tint);
    role!("primary", primary);
    role!("onPrimary", on_primary);
    role!("primaryContainer", primary_container);
    role!("onPrimaryContainer", on_primary_container);
    role!("inversePrimary", inverse_primary);
    role!("secondary", secondary);
    role!("onSecondary", on_secondary);
    role!("secondaryContainer", secondary_container);
    role!("onSecondaryContainer", on_secondary_container);
    role!("tertiary", tertiary);
    role!("onTertiary", on_tertiary);
    role!("tertiaryContainer", tertiary_container);
    role!("onTertiaryContainer", on_tertiary_container);
    role!("error", error);
    role!("onError", on_error);
    role!("errorContainer", error_container);
    role!("onErrorContainer", on_error_container);
    role!("primaryFixed", primary_fixed);
    role!("primaryFixedDim", primary_fixed_dim);
    role!("onPrimaryFixed", on_primary_fixed);
    role!("onPrimaryFixedVariant", on_primary_fixed_variant);
    role!("secondaryFixed", secondary_fixed);
    role!("secondaryFixedDim", secondary_fixed_dim);
    role!("onSecondaryFixed", on_secondary_fixed);
    role!("onSecondaryFixedVariant", on_secondary_fixed_variant);
    role!("tertiaryFixed", tertiary_fixed);
    role!("tertiaryFixedDim", tertiary_fixed_dim);
    role!("onTertiaryFixed", on_tertiary_fixed);
    role!("onTertiaryFixedVariant", on_tertiary_fixed_variant);
    for (name, value) in if options.dark {
        [
            ("success", "#B5CCBA"),
            ("onSuccess", "#213528"),
            ("successContainer", "#374B3E"),
            ("onSuccessContainer", "#D1E9D6"),
        ]
    } else {
        [
            ("success", "#4F6354"),
            ("onSuccess", "#FFFFFF"),
            ("successContainer", "#D1E8D5"),
            ("onSuccessContainer", "#0C1F13"),
        ]
    } {
        output.push_str(&format!("${name}: {value};\n"));
    }
    if let Some(path) = options.termscheme {
        let contents = fs::read_to_string(Path::new(&path))
            .map_err(|error| format!("Could not read terminal scheme: {error}"))?;
        let data: Value = serde_json::from_str(&contents)
            .map_err(|error| format!("Invalid terminal scheme JSON: {error}"))?;
        let mode = if options.dark { "dark" } else { "light" };
        let terms = data[mode]
            .as_object()
            .ok_or("Terminal scheme is missing the selected mode")?;
        for index in 0..16 {
            let name = format!("term{index}");
            let value = terms[&name]
                .as_str()
                .ok_or_else(|| format!("Terminal scheme is missing {name}"))?;
            let source =
                Argb::from_str(value).map_err(|_| format!("Terminal scheme has invalid {name}"))?;
            let result = if options.blend_background_foreground && index == 0 {
                boost(scheme.surface_container_low(), 1.2, 0.95)
            } else if options.blend_background_foreground && index == 15 {
                boost(scheme.on_surface(), 3.0, 1.0)
            } else {
                let harmonized = harmonize(
                    source,
                    scheme.primary_palette_key_color(),
                    options.harmony,
                    options.threshold,
                );
                boost(
                    harmonized,
                    1.0,
                    1.0 + options.foreground_boost * if options.dark { 1.0 } else { -1.0 },
                )
            };
            row(&mut output, &name, result);
        }
    }
    if options.image_source {
        if let Some(path) = options.cache {
            let parent = path.parent().ok_or("Color cache path has no parent")?;
            fs::create_dir_all(parent).map_err(|error| error.to_string())?;
            let staging = parent.join(format!(".nyvorel-color-{}.tmp", std::process::id()));
            let result =
                fs::write(&staging, hex(options.seed)).and_then(|_| fs::rename(&staging, &path));
            if result.is_err() {
                let _ = fs::remove_file(&staging);
            }
            result.map_err(|error| format!("Could not write source color cache: {error}"))?;
        }
    }
    Ok(output)
}
