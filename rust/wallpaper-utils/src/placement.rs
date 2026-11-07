use crate::{image_io, PlacementArgs};
use image::{GrayImage, RgbImage};
use imageproc::{drawing::draw_hollow_rect_mut, rect::Rect};
use serde_json::json;

struct Integral {
    width: usize,
    sum: Vec<u64>,
    square: Vec<u64>,
}

impl Integral {
    fn new(image: &GrayImage) -> Self {
        let width = image.width() as usize + 1;
        let height = image.height() as usize + 1;
        let mut sum = vec![0_u64; width * height];
        let mut square = vec![0_u64; width * height];
        for y in 1..height {
            let mut row_sum = 0_u64;
            let mut row_square = 0_u64;
            for x in 1..width {
                let value = u64::from(image.get_pixel((x - 1) as u32, (y - 1) as u32)[0]);
                row_sum += value;
                row_square += value * value;
                let index = y * width + x;
                sum[index] = sum[index - width] + row_sum;
                square[index] = square[index - width] + row_square;
            }
        }
        Self { width, sum, square }
    }

    fn region_sum(&self, values: &[u64], x: u32, y: u32, w: u32, h: u32) -> u64 {
        let (x0, y0, x1, y1) = (x as usize, y as usize, (x + w) as usize, (y + h) as usize);
        (values[y1 * self.width + x1] + values[y0 * self.width + x0])
            - (values[y0 * self.width + x1] + values[y1 * self.width + x0])
    }

    fn variance(&self, x: u32, y: u32, w: u32, h: u32) -> f64 {
        let area = f64::from(w) * f64::from(h);
        let mean = self.region_sum(&self.sum, x, y, w, h) as f64 / area;
        let square = self.region_sum(&self.square, x, y, w, h) as f64 / area;
        (square - mean * mean).max(0.0)
    }
}

#[derive(Clone, Copy)]
struct Region {
    x: u32,
    y: u32,
    w: u32,
    h: u32,
    variance: f64,
}

fn padding(image: &GrayImage, horizontal: u32, vertical: u32) -> (u32, u32) {
    if horizontal.saturating_mul(2) >= image.width() || vertical.saturating_mul(2) >= image.height()
    {
        (
            horizontal.min(image.width().saturating_sub(1) / 2),
            vertical.min(image.height().saturating_sub(1) / 2),
        )
    } else {
        (horizontal, vertical)
    }
}

fn scan(
    image: &GrayImage,
    integral: &Integral,
    size: (u32, u32),
    padding: (u32, u32),
    stride: u32,
    busiest: bool,
) -> Option<Region> {
    let (w, h) = size;
    let (hp, vp) = padding;
    let max_x = image.width().checked_sub(w + hp)?;
    let max_y = image.height().checked_sub(h + vp)?;
    let mut best: Option<Region> = None;
    for y in (vp..=max_y).step_by(stride as usize) {
        for x in (hp..=max_x).step_by(stride as usize) {
            let variance = integral.variance(x, y, w, h);
            if best.is_none_or(|previous| {
                if busiest {
                    variance > previous.variance
                } else {
                    variance < previous.variance
                }
            }) {
                best = Some(Region {
                    x,
                    y,
                    w,
                    h,
                    variance,
                });
            }
        }
    }
    best
}

fn largest(
    image: &GrayImage,
    integral: &Integral,
    hp: u32,
    vp: u32,
    stride: u32,
    threshold: f64,
    aspect: f64,
) -> Option<Region> {
    let effective_w = image.width().checked_sub(hp * 2)?;
    let effective_h = image.height().checked_sub(vp * 2)?;
    if effective_w == 0 || effective_h == 0 {
        return None;
    }
    let max_size = if aspect >= 1.0 {
        effective_h.min((effective_w as f64 / aspect) as u32)
    } else {
        effective_w.min((effective_h as f64 * aspect) as u32)
    };
    let mut low = 1_u32;
    let mut high = max_size;
    let mut best = None;
    while low <= high {
        let mid = low + (high - low) / 2;
        let (w, h) = if aspect >= 1.0 {
            ((mid as f64 * aspect).round() as u32, mid)
        } else {
            (mid, (mid as f64 / aspect).round() as u32)
        };
        if w == 0 || h == 0 || w > effective_w || h > effective_h {
            high = mid.saturating_sub(1);
            continue;
        }
        let mut found = None;
        let max_x = image.width() - w - hp;
        let max_y = image.height() - h - vp;
        'search: for y in (vp..=max_y).step_by(stride as usize) {
            for x in (hp..=max_x).step_by(stride as usize) {
                let variance = integral.variance(x, y, w, h);
                if variance <= threshold {
                    found = Some(Region {
                        x,
                        y,
                        w,
                        h,
                        variance,
                    });
                    break 'search;
                }
            }
        }
        if let Some(region) = found {
            best = Some(region);
            low = mid + 1;
        } else {
            high = mid.saturating_sub(1);
        }
    }
    best
}

#[derive(Clone, Copy, Default)]
struct Bucket {
    count: u32,
    rgb: [u64; 3],
}

fn dominant_color(image: &RgbImage, region: Region) -> String {
    let mut buckets = vec![Bucket::default(); 32 * 32 * 32];
    let mut colored = 0_u32;
    for y in region.y..region.y + region.h {
        for x in region.x..region.x + region.w {
            let p = image.get_pixel(x, y).0;
            if p.iter().any(|value| *value > 10) {
                colored += 1;
            }
            let index = (usize::from(p[0] >> 3) << 10)
                | (usize::from(p[1] >> 3) << 5)
                | usize::from(p[2] >> 3);
            let bucket = &mut buckets[index];
            bucket.count += 1;
            for (channel, value) in p.iter().enumerate() {
                bucket.rgb[channel] += u64::from(*value);
            }
        }
    }
    let mut ranked: Vec<Bucket> = buckets.into_iter().filter(|item| item.count > 0).collect();
    if colored > 0 {
        ranked.retain(|bucket| {
            bucket
                .rgb
                .iter()
                .any(|sum| *sum > 10 * u64::from(bucket.count))
        });
    }
    ranked.sort_by_key(|bucket| std::cmp::Reverse(bucket.count));
    let Some(best) = ranked.first() else {
        return "#000000".into();
    };
    let total_pixels: u64 = ranked.iter().map(|bucket| u64::from(bucket.count)).sum();
    // A highly varied photo has no stable dominant bucket. Use its mean
    // luminance/color for readable widget text instead of a random bright hue.
    if u64::from(best.count) * 20 < total_pixels {
        let mut channels = [0_u64; 3];
        for bucket in &ranked {
            for (sum, value) in channels.iter_mut().zip(bucket.rgb) {
                *sum += value;
            }
        }
        return format!(
            "#{:02x}{:02x}{:02x}",
            channels[0] / total_pixels,
            channels[1] / total_pixels,
            channels[2] / total_pixels
        );
    }
    // Group neighboring quantized shades around the strongest color mode.
    let center: [f64; 3] = std::array::from_fn(|i| best.rgb[i] as f64 / f64::from(best.count));
    let mut total = [0_u64; 3];
    let mut count = 0_u64;
    for bucket in &ranked {
        let mean: [f64; 3] =
            std::array::from_fn(|i| bucket.rgb[i] as f64 / f64::from(bucket.count));
        let distance = (0..3).map(|i| (mean[i] - center[i]).powi(2)).sum::<f64>();
        if distance <= 45.0_f64.powi(2) {
            for (channel, value) in total.iter_mut().zip(bucket.rgb) {
                *channel += value;
            }
            count += u64::from(bucket.count);
        }
    }
    if count == 0 {
        return "#000000".into();
    }
    format!(
        "#{:02x}{:02x}{:02x}",
        total[0] / count,
        total[1] / count,
        total[2] / count
    )
}

fn draw(image: &mut RgbImage, region: Region, largest: bool) -> Result<(), String> {
    let color = if largest {
        image::Rgb([0, 0, 255])
    } else {
        image::Rgb([255, 0, 0])
    };
    for offset in 0..3_i32 {
        let x = region.x as i32 + offset;
        let y = region.y as i32 + offset;
        let w = region.w.saturating_sub(offset as u32 * 2);
        let h = region.h.saturating_sub(offset as u32 * 2);
        if w > 0 && h > 0 {
            draw_hollow_rect_mut(image, Rect::at(x, y).of_size(w, h), color);
        }
    }
    image
        .save("output.png")
        .map_err(|error| format!("Could not write debug image: {error}"))
}

pub fn run(args: &PlacementArgs) -> Result<(), String> {
    if args.width == 0
        || args.height == 0
        || args.stride == 0
        || args.screen_width == 0
        || args.screen_height == 0
    {
        return Err("Region and screen dimensions and stride must be positive".into());
    }
    if !args.aspect_ratio.is_finite()
        || args.aspect_ratio <= 0.0
        || !args.variance_threshold.is_finite()
    {
        return Err("Aspect ratio and variance threshold must be finite and positive".into());
    }
    let source = image_io::open(&args.image_path)?;
    let rgb = image_io::wallpaper_rgb(
        &source,
        args.screen_width,
        args.screen_height,
        &args.screen_mode,
    )?;
    let gray = GrayImage::from_fn(rgb.width(), rgb.height(), |x, y| {
        let p = rgb.get_pixel(x, y).0;
        let value =
            (77_u32 * u32::from(p[0]) + 150 * u32::from(p[1]) + 29 * u32::from(p[2]) + 128) >> 8;
        image::Luma([value as u8])
    });
    let (hp, vp) = padding(&gray, args.horizontal_padding, args.vertical_padding);
    let integral = Integral::new(&gray);
    let region = if args.largest_region {
        largest(
            &gray,
            &integral,
            hp,
            vp,
            args.stride,
            args.variance_threshold.max(0.0),
            args.aspect_ratio,
        )
    } else {
        let max_w = gray.width().saturating_sub(hp * 2);
        let max_h = gray.height().saturating_sub(vp * 2);
        if max_w == 0 || max_h == 0 {
            return Err("Image too small for the specified padding".into());
        }
        scan(
            &gray,
            &integral,
            (args.width.min(max_w), args.height.min(max_h)),
            (hp, vp),
            args.stride,
            args.busiest,
        )
    };
    let Some(region) = region else {
        println!(
            "{}",
            json!({"error": "No region found under the threshold."})
        );
        return Ok(());
    };
    let color = dominant_color(&rgb, region);
    if args.visual_output {
        draw(&mut rgb.clone(), region, args.largest_region)?;
    }
    if args.verbose {
        eprintln!(
            "Analyzed {}x{} image; region {}x{} at {},{}",
            gray.width(),
            gray.height(),
            region.w,
            region.h,
            region.x,
            region.y
        );
    }
    println!(
        "{}",
        json!({
            "center_x": region.x + region.w / 2,
            "center_y": region.y + region.h / 2,
            "width": region.w,
            "height": region.h,
            "variance": region.variance,
            "dominant_color": color,
        })
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::Integral;
    use image::{GrayImage, Luma};

    #[test]
    fn integral_variance_matches_known_values() {
        let image = GrayImage::from_fn(2, 2, |x, y| Luma([(x + y * 2) as u8]));
        let integral = Integral::new(&image);
        assert!((integral.variance(0, 0, 2, 2) - 1.25).abs() < 1e-9);
        assert_eq!(integral.variance(1, 1, 1, 1), 0.0);
    }
}
