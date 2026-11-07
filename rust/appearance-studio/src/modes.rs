//! Pure Material palette treatments used by preview and committed themes.

use serde_json::{json, Value};

fn rgb(hex: &str) -> Option<[f64; 3]> {
    let raw = hex.strip_prefix('#')?;
    if raw.len() != 6 || !raw.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return None;
    }
    Some([
        u8::from_str_radix(&raw[0..2], 16).ok()? as f64 / 255.0,
        u8::from_str_radix(&raw[2..4], 16).ok()? as f64 / 255.0,
        u8::from_str_radix(&raw[4..6], 16).ok()? as f64 / 255.0,
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

fn perceptual_dim(hex: &str) -> Option<String> {
    let [r, g, b] = rgb(hex)?.map(linear);
    let l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b).cbrt();
    let m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b).cbrt();
    let s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b).cbrt();
    let lightness = (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s) * 0.78;
    let a = (1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s) * 0.96;
    let b = (0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s) * 0.96;
    let lightness = lightness.max(0.025);
    let l = (lightness + 0.3963377774 * a + 0.2158037573 * b).powi(3);
    let m = (lightness - 0.1055613458 * a - 0.0638541728 * b).powi(3);
    let s = (lightness - 0.0894841775 * a - 1.2914855480 * b).powi(3);
    let channels = [
        srgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
        srgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
        srgb(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s),
    ];
    Some(format!(
        "#{:02x}{:02x}{:02x}",
        (channels[0] * 255.0).round_ties_even() as u8,
        (channels[1] * 255.0).round_ties_even() as u8,
        (channels[2] * 255.0).round_ties_even() as u8
    ))
}

fn luminance(hex: &str) -> Option<f64> {
    let [r, g, b] = rgb(hex)?.map(linear);
    Some(0.2126 * r + 0.7152 * g + 0.0722 * b)
}

fn contrast(a: &str, b: &str) -> Option<f64> {
    let (a, b) = (luminance(a)?, luminance(b)?);
    Some((a.max(b) + 0.05) / (a.min(b) + 0.05))
}

fn ensure_contrast(colors: &mut Value, foreground: &str, background: &str) {
    let (Some(fg), Some(bg)) = (colors[foreground].as_str(), colors[background].as_str()) else {
        return;
    };
    let Some(ratio) = contrast(fg, bg) else {
        return;
    };
    if ratio >= 7.0 {
        return;
    }
    let white = contrast("#ffffff", bg).unwrap_or(0.0);
    let black = contrast("#000000", bg).unwrap_or(0.0);
    colors[foreground] = json!(if white >= black { "#ffffff" } else { "#000000" });
}

pub fn apply(colors: &Value, mode: &str) -> Value {
    let mut result = colors.clone();
    if !result.is_object() {
        return result;
    }
    match mode {
        "oled" => {
            for (role, color) in [
                ("background", "#000000"),
                ("surface", "#000000"),
                ("surface_dim", "#000000"),
                ("surface_container_lowest", "#000000"),
                ("surface_container_low", "#030303"),
                ("surface_container", "#070707"),
                ("surface_container_high", "#0c0c0c"),
                ("surface_container_highest", "#121212"),
                ("surface_bright", "#1a1a1a"),
            ] {
                result[role] = json!(color);
            }
        }
        "dim" => {
            for role in [
                "background",
                "surface",
                "surface_dim",
                "surface_bright",
                "surface_variant",
                "surface_container_lowest",
                "surface_container_low",
                "surface_container",
                "surface_container_high",
                "surface_container_highest",
            ] {
                if let Some(dimmed) = result[role].as_str().and_then(perceptual_dim) {
                    result[role] = json!(dimmed);
                }
            }
        }
        "high-contrast" => {
            for (role, color) in [
                ("background", "#000000"),
                ("surface", "#000000"),
                ("surface_dim", "#000000"),
                ("surface_container_lowest", "#000000"),
                ("surface_container_low", "#080808"),
                ("surface_container", "#101010"),
                ("surface_container_high", "#181818"),
                ("surface_container_highest", "#222222"),
                ("on_background", "#ffffff"),
                ("on_surface", "#ffffff"),
                ("on_surface_variant", "#f2f2f2"),
                ("outline", "#f0f0f0"),
                ("outline_variant", "#8c8c8c"),
            ] {
                result[role] = json!(color);
            }
            for (on, base) in [
                ("on_background", "background"),
                ("on_surface", "surface"),
                ("on_surface_variant", "surface_variant"),
                ("on_primary", "primary"),
                ("on_primary_container", "primary_container"),
                ("on_secondary", "secondary"),
                ("on_secondary_container", "secondary_container"),
                ("on_tertiary", "tertiary"),
                ("on_tertiary_container", "tertiary_container"),
                ("on_error", "error"),
                ("on_error_container", "error_container"),
            ] {
                ensure_contrast(&mut result, on, base);
            }
        }
        _ => {}
    }
    result
}

#[cfg(test)]
mod tests {
    use super::apply;
    use serde_json::json;

    #[test]
    fn oled_keeps_accent_and_sets_true_black_surface() {
        let colors = json!({"background":"#345678","primary":"#abcdef"});
        let result = apply(&colors, "oled");
        assert_eq!(result["background"], "#000000");
        assert_eq!(result["primary"], "#abcdef");
    }

    #[test]
    fn high_contrast_repairs_foreground_ratio() {
        let colors = json!({"primary":"#111111","on_primary":"#202020"});
        let result = apply(&colors, "high-contrast");
        assert_eq!(result["on_primary"], "#ffffff");
    }
}
