use crate::{image_io, ThumbnailArgs};
use image::{imageops::FilterType, DynamicImage, GenericImageView};
use std::{
    env, fs,
    fs::{File, OpenOptions},
    io::{BufReader, Write},
    os::unix::ffi::OsStrExt,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant, UNIX_EPOCH},
};

fn cache_root() -> Result<PathBuf, String> {
    if let Some(path) = env::var_os("XDG_CACHE_HOME").filter(|value| !value.is_empty()) {
        return Ok(PathBuf::from(path));
    }
    Ok(PathBuf::from(env::var_os("HOME").ok_or("HOME is unset")?).join(".cache"))
}

fn collect(directory: &Path, recursive: bool, files: &mut Vec<PathBuf>) -> Result<(), String> {
    for entry in fs::read_dir(directory)
        .map_err(|error| format!("Cannot list {}: {error}", directory.display()))?
    {
        let entry = entry.map_err(|error| error.to_string())?;
        let kind = entry.file_type().map_err(|error| error.to_string())?;
        if kind.is_file() {
            files.push(entry.path());
        } else if recursive && kind.is_dir() {
            collect(&entry.path(), true, files)?;
        }
    }
    Ok(())
}

fn file_uri(path: &Path) -> Result<String, String> {
    let absolute = if path.is_absolute() {
        path.to_path_buf()
    } else {
        env::current_dir()
            .map_err(|error| error.to_string())?
            .join(path)
    };
    let mut uri = String::from("file://");
    for &byte in absolute.as_os_str().as_bytes() {
        let allowed = byte.is_ascii_alphanumeric() || b"/-._~:@!$&'()*+,;=".contains(&byte);
        if allowed {
            uri.push(char::from(byte));
        } else {
            uri.push_str(&format!("%{byte:02X}"));
        }
    }
    Ok(uri)
}

fn fresh(path: &Path, uri: &str, mtime: &str) -> bool {
    let Ok(file) = File::open(path) else {
        return false;
    };
    let Ok(reader) = png::Decoder::new(BufReader::new(file)).read_info() else {
        return false;
    };
    let fields = &reader.info().uncompressed_latin1_text;
    fields
        .iter()
        .any(|item| item.keyword == "Thumb::URI" && item.text == uri)
        && fields
            .iter()
            .any(|item| item.keyword == "Thumb::MTime" && item.text == mtime)
}

fn run_bounded(mut command: Command, duration: Duration) -> Result<(), String> {
    command
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    let mut child = command.spawn().map_err(|error| error.to_string())?;
    let deadline = Instant::now() + duration;
    loop {
        match child.try_wait() {
            Ok(Some(status)) if status.success() => return Ok(()),
            Ok(Some(status)) => return Err(format!("Image converter exited with {status}")),
            Ok(None) if Instant::now() < deadline => thread::sleep(Duration::from_millis(20)),
            Ok(None) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err("Image converter timed out".into());
            }
            Err(error) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(error.to_string());
            }
        }
    }
}

fn fallback_image(path: &Path, scratch: &Path, size: u32) -> Result<DynamicImage, String> {
    let extension = path
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    if ["mp4", "webm", "mkv", "avi", "mov"].contains(&extension.as_str()) {
        let mut command = Command::new("ffmpeg");
        command
            .args(["-loglevel", "error", "-y", "-ss", "1", "-i"])
            .arg(path)
            .args(["-frames:v", "1", "-vf"])
            .arg(format!(
                "scale={size}:{size}:force_original_aspect_ratio=decrease"
            ))
            .arg(scratch);
        run_bounded(command, Duration::from_secs(25))?;
    } else {
        let mut command = Command::new("magick");
        command
            .args(["-limit", "memory", "256MiB", "-limit", "time", "20"])
            .arg(format!("{}[0]", path.display()))
            .arg("-thumbnail")
            .arg(format!("{size}x{size}"))
            .arg(format!("PNG:{}", scratch.display()));
        run_bounded(command, Duration::from_secs(25))?;
    }
    let metadata = fs::metadata(scratch).map_err(|error| error.to_string())?;
    if metadata.len() > 20 * 1024 * 1024 {
        return Err("Converted thumbnail exceeds the size limit".into());
    }
    image_io::open(scratch)
}

fn write_png(
    path: &Path,
    image: &DynamicImage,
    uri: &str,
    mtime: &str,
    size: u64,
) -> Result<(), String> {
    let rgba = image.to_rgba8();
    let file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .map_err(|error| format!("Could not create thumbnail {}: {error}", path.display()))?;
    let mut encoder = png::Encoder::new(file, rgba.width(), rgba.height());
    encoder.set_color(png::ColorType::Rgba);
    encoder.set_depth(png::BitDepth::Eight);
    for (name, value) in [
        ("Thumb::URI", uri.to_string()),
        ("Thumb::MTime", mtime.to_string()),
        ("Thumb::Size", size.to_string()),
        ("Software", "Nyvorel Wallpaper Utils".to_string()),
    ] {
        encoder
            .add_text_chunk(name.into(), value)
            .map_err(|error| error.to_string())?;
    }
    let mut writer = encoder.write_header().map_err(|error| error.to_string())?;
    writer
        .write_image_data(&rgba)
        .map_err(|error| error.to_string())?;
    writer.finish().map_err(|error| error.to_string())?;
    Ok(())
}

fn thumbnail(path: &Path, size_name: &str, size: u32, cache: &Path) -> Result<(), String> {
    let metadata = fs::metadata(path).map_err(|error| error.to_string())?;
    let seconds = metadata
        .modified()
        .map_err(|error| error.to_string())?
        .duration_since(UNIX_EPOCH)
        .map_err(|error| error.to_string())?
        .as_secs();
    let mtime = seconds.to_string();
    let uri = file_uri(path)?;
    let hash = format!("{:x}", md5::compute(uri.as_bytes()));
    let folder = cache.join("thumbnails").join(size_name);
    fs::create_dir_all(&folder).map_err(|error| error.to_string())?;
    let output = folder.join(format!("{hash}.png"));
    if fresh(&output, &uri, &mtime) {
        return Ok(());
    }
    let scratch = folder.join(format!(".{hash}-{}-source.png", std::process::id()));
    let source = match image_io::open(path) {
        Ok(image) => image,
        Err(_) => {
            let result = fallback_image(path, &scratch, size);
            let _ = fs::remove_file(&scratch);
            result?
        }
    };
    let (width, height) = source.dimensions();
    let preview = if width > size || height > size {
        source.resize(size, size, FilterType::Lanczos3)
    } else {
        source
    };
    let staging = folder.join(format!(".{hash}-{}.png", std::process::id()));
    let result = write_png(&staging, &preview, &uri, &mtime, metadata.len())
        .and_then(|_| fs::rename(&staging, &output).map_err(|error| error.to_string()));
    if result.is_err() {
        let _ = fs::remove_file(&staging);
    }
    result
}

pub fn run(args: &ThumbnailArgs) -> Result<(), String> {
    if args.workers == 0 {
        return Err("Workers must be at least one".into());
    }
    let size = match args.size.as_str() {
        "normal" => 128,
        "large" => 256,
        "x-large" => 512,
        "xx-large" => 1024,
        _ => return Err("Invalid thumbnail size".into()),
    };
    let cache = cache_root()?;
    let mut files = Vec::new();
    let directories: Vec<&str> = if Path::new(&args.img_dirs).is_dir() {
        vec![args.img_dirs.as_str()]
    } else {
        args.img_dirs.split_whitespace().collect()
    };
    for directory in directories {
        let path = Path::new(directory);
        if !path.is_dir() {
            return Err(format!("{} is not a directory", path.display()));
        }
        collect(path, args.recursive, &mut files)?;
    }
    if args.only_images {
        files.retain(|path| {
            matches!(
                path.extension().and_then(|v| v.to_str()),
                Some("jpg" | "jpeg" | "png" | "gif")
            )
        });
    }
    files.retain(|path| {
        let extension = path
            .extension()
            .and_then(|value| value.to_str())
            .unwrap_or("")
            .to_ascii_lowercase();
        matches!(
            extension.as_str(),
            "jpg"
                | "jpeg"
                | "png"
                | "gif"
                | "webp"
                | "avif"
                | "bmp"
                | "svg"
                | "mp4"
                | "webm"
                | "mkv"
                | "avi"
                | "mov"
        )
    });
    files.sort();
    files.dedup();
    let total = files.len();
    let mut completed = 0;
    let mut failures = 0;
    for chunk in files.chunks(args.workers.min(4)) {
        let results = thread::scope(|scope| {
            let handles: Vec<_> = chunk
                .iter()
                .map(|path| {
                    let cache = &cache;
                    let size_name = &args.size;
                    scope.spawn(move || thumbnail(path, size_name, size, cache))
                })
                .collect();
            handles
                .into_iter()
                .map(|handle| {
                    handle
                        .join()
                        .unwrap_or_else(|_| Err("Thumbnail worker panicked".into()))
                })
                .collect::<Vec<_>>()
        });
        for (path, result) in chunk.iter().zip(results) {
            completed += 1;
            if let Err(error) = result {
                failures += 1;
                eprintln!("Thumbnail {}: {error}", path.display());
            }
            if args.machine_progress {
                println!("PROGRESS {completed}/{total} FILE {}", path.display());
                std::io::stdout()
                    .flush()
                    .map_err(|error| error.to_string())?;
            }
        }
    }
    if !args.machine_progress {
        println!("Thumbnail Generation Completed!");
    }
    if failures > 0 {
        Err(format!("{failures} thumbnail(s) failed"))
    } else {
        Ok(())
    }
}
