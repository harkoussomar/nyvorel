use image::{imageops::FilterType, DynamicImage, RgbImage};
use std::path::Path;

const MAX_INPUT_PIXELS: u64 = 80_000_000;
const MAX_WORK_PIXELS: u64 = 32_000_000;

pub fn open(path: &Path) -> Result<DynamicImage, String> {
    let (width, height) = image::image_dimensions(path)
        .map_err(|error| format!("Could not inspect image {}: {error}", path.display()))?;
    if width == 0 || height == 0 || u64::from(width) * u64::from(height) > MAX_INPUT_PIXELS {
        return Err(format!(
            "Image dimensions are unsupported: {}",
            path.display()
        ));
    }
    image::open(path).map_err(|error| format!("Could not load image {}: {error}", path.display()))
}

fn scaled_dimensions(
    width: u32,
    height: u32,
    target_w: u32,
    target_h: u32,
    mode: &str,
) -> Result<(u32, u32), String> {
    if target_w == 0 || target_h == 0 || width == 0 || height == 0 {
        return Err("Image or target dimensions must be positive".into());
    }
    if u64::from(target_w) * u64::from(target_h) > MAX_WORK_PIXELS {
        return Err("Requested display image exceeds the 32 megapixel work limit".into());
    }
    let width_scale = target_w as f64 / width as f64;
    let height_scale = target_h as f64 / height as f64;
    let scale = if mode == "fill" {
        width_scale.max(height_scale)
    } else {
        width_scale.min(height_scale)
    };
    let new_width = ((width as f64 * scale) as u32).max(1);
    let new_height = ((height as f64 * scale) as u32).max(1);
    if u64::from(new_width) * u64::from(new_height) > MAX_WORK_PIXELS * 2 {
        return Err("Scaled image exceeds the work limit".into());
    }
    Ok((new_width, new_height))
}

pub fn wallpaper_rgb(
    image: &DynamicImage,
    target_w: u32,
    target_h: u32,
    mode: &str,
) -> Result<RgbImage, String> {
    let (new_w, new_h) =
        scaled_dimensions(image.width(), image.height(), target_w, target_h, mode)?;
    let rgb = image.to_rgb8();
    let scaled = image::imageops::resize(&rgb, new_w, new_h, FilterType::Lanczos3);
    Ok(center_crop_rgb(&scaled, target_w, target_h))
}

fn center_crop_rgb(image: &RgbImage, target_w: u32, target_h: u32) -> RgbImage {
    let x = image.width().saturating_sub(target_w) / 2;
    let y = image.height().saturating_sub(target_h) / 2;
    image::imageops::crop_imm(
        image,
        x,
        y,
        target_w.min(image.width()),
        target_h.min(image.height()),
    )
    .to_image()
}
