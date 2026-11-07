//! Bounded image sampling for the ordinary wallpaper color path.

use image::{
    codecs::gif::GifDecoder, imageops::FilterType, AnimationDecoder, DynamicImage, GenericImageView,
};
use material_colors::{
    color::Argb,
    quantize::{Quantizer, QuantizerCelebi},
    score::Score,
};
use std::{
    fs,
    io::BufReader,
    path::Path,
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

const MAX_INPUT_PIXELS: u64 = 80_000_000;

fn open(path: &Path) -> Result<DynamicImage, String> {
    if !path.is_file() {
        return Err(format!("Image does not exist: {}", path.display()));
    }
    let (width, height) = match image::image_dimensions(path) {
        Ok(dimensions) => dimensions,
        Err(_) => return converted_preview(path),
    };
    if width == 0 || height == 0 || u64::from(width) * u64::from(height) > MAX_INPUT_PIXELS {
        return Err(format!("Unsupported image dimensions: {}", path.display()));
    }
    if path
        .extension()
        .and_then(|value| value.to_str())
        .is_some_and(|value| value.eq_ignore_ascii_case("gif"))
    {
        let source = fs::File::open(path).map_err(|error| error.to_string())?;
        let decoder = GifDecoder::new(BufReader::new(source)).map_err(|error| error.to_string())?;
        let mut frames = decoder.into_frames();
        let first = frames
            .next()
            .ok_or("GIF has no image frame")?
            .map_err(|error| error.to_string())?;
        let chosen = match frames.next() {
            Some(frame) => frame.map_err(|error| error.to_string())?,
            None => first,
        };
        return Ok(DynamicImage::ImageRgba8(chosen.into_buffer()));
    }
    match image::open(path) {
        Ok(image) => Ok(image),
        Err(_) => converted_preview(path),
    }
}

fn converted_preview(path: &Path) -> Result<DynamicImage, String> {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| error.to_string())?
        .as_nanos();
    let directory =
        std::env::temp_dir().join(format!("nyvorel-color-{}-{nonce}", std::process::id()));
    fs::create_dir(&directory).map_err(|error| error.to_string())?;
    let destination = directory.join("preview.png");
    let result = (|| {
        let mut child = Command::new("magick")
            .args([
                "-limit", "memory", "256MiB", "-limit", "disk", "256MiB", "-limit", "time", "20",
            ])
            .arg(format!("{}[0]", path.display()))
            .args(["-resize", "192x192"])
            .arg(format!("PNG:{}", destination.display()))
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|error| format!("Could not start image converter: {error}"))?;
        let deadline = Instant::now() + Duration::from_secs(25);
        loop {
            match child.try_wait() {
                Ok(Some(status)) if status.success() => break,
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
        if fs::metadata(&destination)
            .map_err(|error| error.to_string())?
            .len()
            > 20 * 1024 * 1024
        {
            return Err("Converted image exceeds size limit".into());
        }
        image::open(&destination).map_err(|error| error.to_string())
    })();
    let _ = fs::remove_dir_all(directory);
    result
}

fn resize_to_area(image: DynamicImage, size: u32) -> Result<image::RgbImage, String> {
    if !(1..=1024).contains(&size) {
        return Err("Image sample size must be between 1 and 1024".into());
    }
    let (width, height) = image.dimensions();
    let target_area = f64::from(size) * f64::from(size);
    let area = f64::from(width) * f64::from(height);
    let scale = if area > target_area {
        (target_area / area).sqrt()
    } else {
        1.0
    };
    let target_width = (f64::from(width) * scale).round_ties_even().max(1.0) as u32;
    let target_height = (f64::from(height) * scale).round_ties_even().max(1.0) as u32;
    if target_width == width && target_height == height {
        Ok(image.to_rgb8())
    } else {
        Ok(image
            .resize_exact(target_width, target_height, FilterType::CatmullRom)
            .to_rgb8())
    }
}

pub fn source_color(path: &Path, size: u32) -> Result<Argb, String> {
    let sampled = resize_to_area(open(path)?, size)?;
    let pixels: Vec<Argb> = sampled
        .pixels()
        .map(|pixel| Argb::new(255, pixel[0], pixel[1], pixel[2]))
        .collect();
    let quantized = QuantizerCelebi::quantize(&pixels, 128);
    Score::score(&quantized.color_to_count, None, None, None)
        .into_iter()
        .next()
        .ok_or_else(|| "Image contains no usable color".into())
}

pub fn colorfulness(path: &Path) -> Result<f64, String> {
    let image = open(path)?;
    let longest = image.width().max(image.height());
    let sampled = if longest > 128 {
        let scale = 128.0 / f64::from(longest);
        image
            .resize_exact(
                (f64::from(image.width()) * scale).floor().max(1.0) as u32,
                (f64::from(image.height()) * scale).floor().max(1.0) as u32,
                FilterType::Triangle,
            )
            .to_rgb8()
    } else {
        image.to_rgb8()
    };
    let count = f64::from(sampled.width()) * f64::from(sampled.height());
    let mut rg_sum = 0.0;
    let mut yb_sum = 0.0;
    let mut rg_square = 0.0;
    let mut yb_square = 0.0;
    for pixel in sampled.pixels() {
        let r = f64::from(pixel[0]);
        let g = f64::from(pixel[1]);
        let b = f64::from(pixel[2]);
        let rg = (r - g).abs();
        let yb = ((r + g) / 2.0 - b).abs();
        rg_sum += rg;
        yb_sum += yb;
        rg_square += rg * rg;
        yb_square += yb * yb;
    }
    let mean_rg = rg_sum / count;
    let mean_yb = yb_sum / count;
    let std_rg = (rg_square / count - mean_rg * mean_rg).max(0.0).sqrt();
    let std_yb = (yb_square / count - mean_yb * mean_yb).max(0.0).sqrt();
    Ok(std_rg.hypot(std_yb) + 0.3 * mean_rg.hypot(mean_yb))
}

pub fn scheme(args: &[String]) -> Result<String, String> {
    let mut path = None;
    let mut report_colorfulness = false;
    for arg in args {
        if arg == "--colorfulness" {
            report_colorfulness = true;
        } else if path.replace(arg).is_some() {
            return Err("Expected one image path".into());
        }
    }
    let path = path.ok_or("Expected an image path")?;
    let value = colorfulness(Path::new(path))?;
    if report_colorfulness {
        Ok(value.to_string())
    } else if value < 40.0 {
        Ok("scheme-neutral".into())
    } else {
        Ok("scheme-tonal-spot".into())
    }
}
