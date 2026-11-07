//! Optional Kvantum theme writers. They run only when the shell explicitly calls them.

use regex::{Captures, Regex, RegexBuilder};
use std::{
    collections::HashMap,
    env, fs,
    io::Write,
    path::{Path, PathBuf},
};

const LIGHT: &[(&str, &str)] = &[
    ("#3c84f7", "primary"),
    ("#000000", "shadow"),
    ("#f04a50", "error"),
    ("#4285f4", "primaryFixedDim"),
    ("#f2f2f2", "background"),
    ("#ffffff", "background"),
    ("#1e1e1e", "onPrimaryFixed"),
    ("#333", "inverseSurface"),
    ("#212121", "onSecondaryFixed"),
    ("#5b9bf8", "secondaryContainer"),
    ("#26272a", "term7"),
    ("#444444", "onBackground"),
    ("#333333", "onPrimaryFixed"),
];

const DARK: &[(&str, &str)] = &[
    ("#31363b", "background"),
    ("#000000", "shadow"),
    ("#5b9bf8", "primary"),
    ("#93cee9", "onSecondaryContainer"),
    ("#3daee9", "secondary"),
    ("#ffffff", "term11"),
    ("#5a616e", "surfaceVariant"),
    ("#f04a50", "error"),
    ("#4285f4", "secondary"),
    ("#242424", "background"),
    ("#2c2c2c", "background"),
    ("#1e1e1e", "background"),
    ("#3c3c3c", "background"),
    ("#26272a", "surfaceBright"),
    ("#b74aff", "tertiary"),
    ("#1a1a1a", "background"),
    ("#333", "term0"),
    ("#212121", "background"),
];

const CONFIG: &[(&str, &str)] = &[
    ("window.color", "background"),
    ("base.color", "background"),
    ("alt.base.color", "background"),
    ("button.color", "surfaceContainer"),
    ("light.color", "surfaceContainerLow"),
    ("mid.light.color", "surfaceContainer"),
    ("dark.color", "surfaceContainerHighest"),
    ("mid.color", "surfaceContainerHigh"),
    ("highlight.color", "primary"),
    ("inactive.highlight.color", "primary"),
    ("text.color", "onBackground"),
    ("window.text.color", "onBackground"),
    ("button.text.color", "onBackground"),
    ("disabled.text.color", "onBackground"),
    ("tooltip.text.color", "onBackground"),
    ("highlight.text.color", "onSurface"),
    ("link.color", "tertiary"),
    ("link.visited.color", "tertiaryFixed"),
    ("progress.indicator.text.color", "onBackground"),
    ("text.normal.color", "onBackground"),
    ("text.focus.color", "onBackground"),
    ("text.press.color", "onSecondaryContainer"),
    ("text.toggle.color", "onSecondaryContainer"),
    ("text.disabled.color", "surfaceDim"),
];

fn xdg(name: &str, fallback: &str) -> Result<PathBuf, String> {
    if let Some(value) = env::var_os(name).filter(|value| !value.is_empty()) {
        return Ok(PathBuf::from(value));
    }
    let home = env::var_os("HOME").ok_or("HOME is unset")?;
    Ok(PathBuf::from(home).join(fallback))
}

fn colors() -> Result<HashMap<String, String>, String> {
    let path = xdg("XDG_STATE_HOME", ".local/state")?
        .join("quickshell/user/generated/material_colors.scss");
    let source = fs::read_to_string(&path)
        .map_err(|error| format!("Could not read {}: {error}", path.display()))?;
    let row =
        Regex::new(r"(?m)^\$(\w+):\s*(#[0-9A-Fa-f]{6});").map_err(|error| error.to_string())?;
    Ok(row
        .captures_iter(&source)
        .map(|capture| (capture[1].to_string(), capture[2].to_string()))
        .collect())
}

fn atomic_write(path: &Path, contents: &str) -> Result<(), String> {
    if path.is_symlink() {
        return Err(format!("Refusing symlink output: {}", path.display()));
    }
    let parent = path.parent().ok_or("Output has no parent directory")?;
    fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    let staging = parent.join(format!(".nyvorel-kvantum-{}.tmp", std::process::id()));
    let result = (|| {
        let mut file = fs::File::create(&staging).map_err(|error| error.to_string())?;
        file.write_all(contents.as_bytes())
            .map_err(|error| error.to_string())?;
        file.sync_all().map_err(|error| error.to_string())?;
        fs::rename(&staging, path).map_err(|error| error.to_string())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&staging);
    }
    result
}

pub fn svg(mode: &str) -> Result<(), String> {
    let mapping = match mode {
        "light" => LIGHT,
        "dark" => DARK,
        _ => return Err("Kvantum mode must be light or dark".into()),
    };
    let palette = colors()?;
    let replacements: HashMap<String, String> = mapping
        .iter()
        .map(|(literal, role)| {
            palette
                .get(*role)
                .map(|color| (literal.to_string(), color.clone()))
                .ok_or_else(|| format!("Material palette is missing {role}"))
        })
        .collect::<Result<_, _>>()?;
    let config = xdg("XDG_CONFIG_HOME", ".config")?;
    let source = config.join(format!(
        "Kvantum/Colloid/Colloid{}.svg",
        if mode == "dark" { "Dark" } else { "" }
    ));
    let destination = config.join("Kvantum/MaterialAdw/MaterialAdw.svg");
    let body = fs::read_to_string(&source)
        .map_err(|error| format!("Could not read {}: {error}", source.display()))?;
    let colors = RegexBuilder::new(r"#[0-9a-f]{6}|#[0-9a-f]{3}")
        .case_insensitive(true)
        .build()
        .map_err(|error| error.to_string())?;
    let updated = colors.replace_all(&body, |capture: &Captures<'_>| {
        replacements
            .get(&capture[0].to_ascii_lowercase())
            .cloned()
            .unwrap_or_else(|| capture[0].to_string())
    });
    atomic_write(&destination, &updated)
}

pub fn config() -> Result<(), String> {
    let palette = colors()?;
    let path = xdg("XDG_CONFIG_HOME", ".config")?.join("Kvantum/MaterialAdw/MaterialAdw.kvconfig");
    let original = fs::read_to_string(&path)
        .map_err(|error| format!("Could not read {}: {error}", path.display()))?;
    let mut lines: Vec<String> = original.lines().map(str::to_string).collect();
    for (key, role) in CONFIG {
        let Some(color) = palette.get(*role) else {
            continue;
        };
        let prefix = format!("{key}=");
        let mut found = false;
        for line in &mut lines {
            if line.starts_with(&prefix) {
                *line = format!("{prefix}{color}");
                found = true;
            }
        }
        if !found {
            lines.push(format!("{prefix}{color}"));
        }
    }
    let mut output = lines.join("\n");
    output.push('\n');
    atomic_write(&path, &output)
}
