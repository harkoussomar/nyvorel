//! One-shot Hyprland keybind parser for the Nyvorel cheatsheet.

use regex::Regex;
use serde::Serialize;
use std::{
    env, fs,
    path::{Path, PathBuf},
    process,
};

#[derive(Default, Serialize)]
struct Section {
    children: Vec<Section>,
    keybinds: Vec<KeyBinding>,
    name: String,
}

impl Section {
    fn named(name: &str) -> Self {
        Self {
            name: name.to_owned(),
            ..Self::default()
        }
    }
}

#[derive(Serialize)]
struct KeyBinding {
    mods: Vec<String>,
    key: String,
    dispatcher: String,
    params: String,
    comment: String,
}

fn expand_path(raw: &str) -> PathBuf {
    let vars = Regex::new(r"\$\{([^}]+)\}|\$([A-Za-z_][A-Za-z_0-9]*)").unwrap();
    let expanded = vars.replace_all(raw, |captures: &regex::Captures<'_>| {
        let name = captures
            .get(1)
            .or_else(|| captures.get(2))
            .unwrap()
            .as_str();
        env::var(name).unwrap_or_else(|_| captures[0].to_owned())
    });
    if let Some(relative) = expanded.strip_prefix("~/") {
        if let Some(home) = env::var_os("HOME") {
            return PathBuf::from(home).join(relative);
        }
    }
    PathBuf::from(expanded.into_owned())
}

fn capitalize(raw: &str) -> String {
    let lower = raw.replace('_', " ").to_lowercase();
    let mut chars = lower.chars();
    match chars.next() {
        Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
        None => String::new(),
    }
}

fn lua(path: &Path) -> Result<Section, String> {
    let source = fs::read_to_string(path)
        .map_err(|error| format!("Could not read {}: {error}", path.display()))?;
    let call = Regex::new(r#"^\s*hl\.bind(?:_release|_repeat)?\(\s*("(?:\\.|[^"\\])*")"#)
        .map_err(|error| error.to_string())?;
    let description = Regex::new(r#"\["description"\]\s*=\s*("(?:\\.|[^"\\])*")"#)
        .map_err(|error| error.to_string())?;
    let action = Regex::new(r"hl\.dsp\.([a-zA-Z_]+)").map_err(|error| error.to_string())?;
    let mut binds = Vec::new();
    for line in source.lines() {
        let Some(found) = call.captures(line) else {
            continue;
        };
        let combo: String = serde_json::from_str(&found[1])
            .map_err(|error| format!("Invalid keybind string in {}: {error}", path.display()))?;
        let tail = &line[found.get(0).unwrap().end()..];
        let comment = if let Some(found) = description.captures(tail) {
            serde_json::from_str::<String>(&found[1])
                .map_err(|error| format!("Invalid description in {}: {error}", path.display()))?
        } else {
            String::new()
        };
        let comment = if comment.is_empty() {
            action
                .captures(tail)
                .map(|capture| capitalize(&capture[1]))
                .unwrap_or_default()
        } else {
            comment
        };
        let mut pieces: Vec<&str> = combo.split('+').map(str::trim).collect();
        let key = pieces.pop().unwrap_or(&combo).to_owned();
        let mods = pieces
            .into_iter()
            .filter(|part| !part.is_empty())
            .map(str::to_owned)
            .collect();
        binds.push(KeyBinding {
            mods,
            key,
            dispatcher: "lua".into(),
            params: String::new(),
            comment,
        });
    }
    Ok(Section {
        children: vec![Section {
            children: vec![Section {
                children: vec![],
                keybinds: binds,
                name: "Nyvorel".into(),
            }],
            keybinds: vec![],
            name: "Hyprland".into(),
        }],
        ..Section::default()
    })
}

fn generated_comment(dispatcher: &str, params: &str) -> String {
    let direction = |p: &str| match p {
        "l" => "left",
        "r" => "right",
        "u" => "up",
        "d" => "down",
        _ => "null",
    };
    match dispatcher {
        "resizewindow" => "Resize window".into(),
        "movewindow" if params.is_empty() => "Move window".into(),
        "movewindow" => format!("Window: move in {} direction", direction(params)),
        "pin" => "Window: pin (show on all workspaces)".into(),
        "splitratio" => format!("Window split ratio {params}"),
        "togglefloating" => "Float/unfloat window".into(),
        "resizeactive" => format!("Resize window by {params}"),
        "killactive" => "Close window".into(),
        "fullscreen" => format!(
            "Toggle {}",
            match params {
                "0" => "fullscreen",
                "1" => "maximization",
                "2" => "fullscreen on Hyprland's side",
                _ => "null",
            }
        ),
        "fakefullscreen" => "Toggle fake fullscreen".into(),
        "workspace" if params == "+1" => "Workspace: focus right".into(),
        "workspace" if params == "-1" => "Workspace: focus left".into(),
        "workspace" => format!("Focus workspace {params}"),
        "movefocus" => format!("Window: move focus {}", direction(params)),
        "swapwindow" => format!("Window: swap in {} direction", direction(params)),
        "movetoworkspace" if params == "+1" => {
            "Window: move to right workspace (non-silent)".into()
        }
        "movetoworkspace" if params == "-1" => "Window: move to left workspace (non-silent)".into(),
        "movetoworkspace" => format!("Window: move to workspace {params} (non-silent)"),
        "movetoworkspacesilent" if params == "+1" || params == "-1" => {
            "Window: move to right workspace".into()
        }
        "movetoworkspacesilent" => format!("Window: move to workspace {params}"),
        "togglespecialworkspace" => "Workspace: toggle special".into(),
        "exec" => format!("Execute: {params}"),
        _ => String::new(),
    }
}

fn conf_binding(line: &str) -> Result<Option<KeyBinding>, String> {
    let (_, assignment) = line.split_once('=').ok_or("Keybind has no assignment")?;
    let (keys, inline_comment) = assignment
        .split_once('#')
        .map_or((assignment, None), |(a, b)| (a, Some(b.trim())));
    let parts: Vec<&str> = keys.splitn(5, ',').map(str::trim).collect();
    if parts.len() < 3 {
        return Err("Keybind needs modifiers, key, and dispatcher".into());
    }
    let (mods_raw, key, dispatcher) = (parts[0], parts[1], parts[2]);
    let params = parts[3..]
        .iter()
        .map(|part| part.trim())
        .collect::<String>();
    let comment = match inline_comment {
        Some(value) if value.starts_with("[hidden]") => return Ok(None),
        Some(value) => value.to_owned(),
        None => generated_comment(dispatcher, &params),
    };
    let mut mods = Vec::new();
    if !mods_raw.is_empty() {
        let chars: Vec<char> = mods_raw.chars().chain(std::iter::once('+')).collect();
        let mut start = 0;
        for (index, character) in chars.iter().enumerate() {
            if *character == '+' || *character == ' ' {
                if index.saturating_sub(start) > 1 {
                    mods.push(chars[start..index].iter().collect());
                }
                start = index + 1;
            }
        }
    }
    Ok(Some(KeyBinding {
        mods,
        key: key.into(),
        dispatcher: dispatcher.into(),
        params,
        comment,
    }))
}

fn conf_section(
    lines: &[&str],
    position: &mut usize,
    scope: usize,
    mut section: Section,
) -> Result<Section, String> {
    while *position < lines.len() {
        let line = lines[*position];
        let hashes = line.bytes().take_while(|byte| *byte == b'#').count();
        if hashes > 0 && line.as_bytes().get(hashes) == Some(&b'!') {
            let title = hashes;
            if title <= scope {
                *position = position.saturating_sub(1);
                return Ok(section);
            }
            *position += 1;
            section.children.push(conf_section(
                lines,
                position,
                title,
                Section::named(line[title + 1..].trim()),
            )?);
        } else if line.starts_with("#/#") || line.trim_start().starts_with("bind") {
            if let Some(binding) = conf_binding(line)? {
                section.keybinds.push(binding);
            }
        }
        *position += 1;
    }
    Ok(section)
}

fn conf(path: &Path) -> Result<Section, String> {
    let source = fs::read_to_string(path)
        .map_err(|error| format!("Could not read {}: {error}", path.display()))?;
    let lines: Vec<&str> = source.lines().collect();
    conf_section(&lines, &mut 0, 0, Section::default())
}

fn parse(raw: &str) -> Result<Section, String> {
    let path = expand_path(raw);
    if path
        .extension()
        .and_then(|value| value.to_str())
        .is_some_and(|value| value.eq_ignore_ascii_case("lua"))
    {
        return lua(&path);
    }
    let parent = path.parent().ok_or("Keybind path has no parent")?;
    let native = if parent.file_name().is_some_and(|value| value == "hypr") {
        parent.join("hyprland.lua")
    } else {
        parent
            .parent()
            .ok_or("Keybind path has no ancestor")?
            .join("hyprland.lua")
    };
    if native.is_file() {
        if parent.file_name().is_some_and(|value| value == "custom") {
            return Ok(Section::default());
        }
        return lua(&native);
    }
    conf(&path)
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let path = match args.as_slice() {
        [] => "$HOME/.config/hypr/hyprland.conf",
        [flag, value] if flag == "--path" => value,
        _ => {
            eprintln!("Usage: nyvorel-keybinds [--path FILE]");
            process::exit(2);
        }
    };
    match parse(path)
        .and_then(|value| serde_json::to_string(&value).map_err(|error| error.to_string()))
    {
        Ok(output) => println!("{output}"),
        Err(error) => {
            eprintln!("{error}");
            process::exit(1);
        }
    }
}
