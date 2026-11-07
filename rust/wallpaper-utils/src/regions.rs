use crate::{image_io, RegionArgs};
use image::{GrayImage, RgbImage};
use imageproc::{
    contours::find_contours,
    drawing::draw_hollow_rect_mut,
    edges::canny,
    geometry::approximate_polygon_dp,
    morphology::{grayscale_close, Mask},
    rect::Rect,
};
use serde_json::{json, Value};

#[derive(Clone)]
struct Candidate {
    x: u32,
    y: u32,
    width: u32,
    height: u32,
    score: f64,
    rectangularity: f64,
    edge_support: f64,
    area_ratio: f64,
    vertices: usize,
    radius: f64,
    radius_confidence: f64,
}

fn lab(pixel: image::Rgb<u8>) -> [f64; 3] {
    let rgb: [f64; 3] = pixel.0.map(|value| {
        let normalized = f64::from(value) / 255.0;
        if normalized <= 0.04045 {
            normalized / 12.92
        } else {
            ((normalized + 0.055) / 1.055).powf(2.4)
        }
    });
    let x = (0.4124564 * rgb[0] + 0.3575761 * rgb[1] + 0.1804375 * rgb[2]) / 0.95047;
    let y = 0.2126729 * rgb[0] + 0.7151522 * rgb[1] + 0.0721750 * rgb[2];
    let z = (0.0193339 * rgb[0] + 0.1191920 * rgb[1] + 0.9503041 * rgb[2]) / 1.08883;
    let f = |v: f64| {
        if v > 0.008856 {
            v.cbrt()
        } else {
            7.787 * v + 16.0 / 116.0
        }
    };
    let (fx, fy, fz) = (f(x), f(y), f(z));
    [
        (116.0 * fy - 16.0) * 2.55,
        500.0 * (fx - fy) + 128.0,
        200.0 * (fy - fz) + 128.0,
    ]
}

fn median(values: &mut [f64]) -> f64 {
    values.sort_by(f64::total_cmp);
    if values.is_empty() {
        0.0
    } else if values.len().is_multiple_of(2) {
        (values[values.len() / 2 - 1] + values[values.len() / 2]) / 2.0
    } else {
        values[values.len() / 2]
    }
}

fn patch(image: &RgbImage, x: i32, y: i32, radius: i32) -> [f64; 3] {
    let mut channels = [Vec::new(), Vec::new(), Vec::new()];
    for yy in (y - radius).max(0)..=(y + radius).min(image.height() as i32 - 1) {
        for xx in (x - radius).max(0)..=(x + radius).min(image.width() as i32 - 1) {
            let pixel = lab(*image.get_pixel(xx as u32, yy as u32));
            for i in 0..3 {
                channels[i].push(pixel[i]);
            }
        }
    }
    channels.each_mut().map(|values| median(values))
}

fn distance(a: [f64; 3], b: [f64; 3]) -> f64 {
    (0..3).map(|i| (a[i] - b[i]).powi(2)).sum::<f64>().sqrt()
}

fn transition_distance(
    pixels: impl Iterator<Item = [f64; 3]>,
    outside: [f64; 3],
    inside: [f64; 3],
    contrast: f64,
) -> Option<usize> {
    let tolerance = (contrast * 0.05).max(1.5);
    let mut previous: Option<usize> = None;
    for (index, pixel) in pixels.enumerate() {
        if distance(pixel, inside) + tolerance < distance(pixel, outside) {
            if index > 0 && previous == Some(index - 1) {
                return previous;
            }
            previous = Some(index);
        } else {
            previous = None;
        }
    }
    None
}

fn radius_from_arc(gap: usize, inward: usize) -> f64 {
    let (gap, inward) = (gap as f64, inward as f64);
    gap + inward + (2.0 * gap * inward).sqrt()
}

fn estimate_radius(image: &RgbImage, x: u32, y: u32, w: u32, h: u32) -> (f64, f64) {
    let min_dim = w.min(h);
    if min_dim < 24 {
        return (0.0, 0.0);
    }
    let inner = 32.min((min_dim / 4).max(10)) as i32;
    let patch_radius = 4.min((min_dim / 20).max(2)) as i32;
    let scan_depth = 7.min((min_dim / 10).max(3)) as usize;
    let scan_limit = 64.min((min_dim / 2).max(10)) as usize;
    let mut radii = Vec::new();
    let mut contrasts = Vec::new();
    for &(sx, sy) in &[(1_i32, 1_i32), (-1, 1), (1, -1), (-1, -1)] {
        let local_x = if sx > 0 { 2 } else { w as i32 - 3 };
        let local_y = if sy > 0 { 2 } else { h as i32 - 3 };
        let surface_x = if sx > 0 { inner } else { w as i32 - 1 - inner };
        let surface_y = if sy > 0 { inner } else { h as i32 - 1 - inner };
        let outside = patch(image, x as i32 + local_x, y as i32 + local_y, patch_radius);
        let inside = patch(
            image,
            x as i32 + surface_x,
            y as i32 + surface_y,
            patch_radius + 1,
        );
        let contrast = distance(outside, inside);
        if contrast < 8.0 {
            continue;
        }
        let mut estimates = Vec::new();
        for inward in 1..=scan_depth {
            let row_y = if sy > 0 {
                inward as i32
            } else {
                h as i32 - 1 - inward as i32
            };
            let row = (0..scan_limit).map(|offset| {
                let local = if sx > 0 {
                    offset as i32
                } else {
                    w as i32 - 1 - offset as i32
                };
                lab(*image.get_pixel((x as i32 + local) as u32, (y as i32 + row_y) as u32))
            });
            if let Some(gap) = transition_distance(row, outside, inside, contrast) {
                estimates.push(radius_from_arc(gap, inward));
            }
            let column_x = if sx > 0 {
                inward as i32
            } else {
                w as i32 - 1 - inward as i32
            };
            let column = (0..scan_limit).map(|offset| {
                let local = if sy > 0 {
                    offset as i32
                } else {
                    h as i32 - 1 - offset as i32
                };
                lab(*image.get_pixel((x as i32 + column_x) as u32, (y as i32 + local) as u32))
            });
            if let Some(gap) = transition_distance(column, outside, inside, contrast) {
                estimates.push(radius_from_arc(gap, inward));
            }
        }
        if estimates.len() < 3 {
            continue;
        }
        let radius = median(&mut estimates);
        if radius >= 3.0 {
            radii.push(radius);
            contrasts.push(contrast);
        }
    }
    if radii.len() < 3 {
        return (0.0, 0.0);
    }
    let radius = median(&mut radii);
    if radius < 4.0 || radius > 64.0_f64.min(f64::from(min_dim) * 0.45) {
        return (0.0, 0.0);
    }
    let mut deviations: Vec<f64> = radii.iter().map(|value| (value - radius).abs()).collect();
    let deviation = median(&mut deviations);
    let consistency = (1.0 - deviation / (radius * 0.35).max(2.0)).max(0.0);
    let contrast = median(&mut contrasts);
    let confidence = consistency * 0.55 + ((contrast - 8.0) / 24.0).clamp(0.0, 1.0) * 0.45;
    if confidence < 0.58 {
        (0.0, (confidence * 1000.0).round() / 1000.0)
    } else {
        (
            (radius * 10.0).round() / 10.0,
            (confidence * 1000.0).round() / 1000.0,
        )
    }
}

fn polygon_area(points: &[imageproc::point::Point<i32>]) -> f64 {
    if points.len() < 3 {
        return 0.0;
    }
    let mut twice = 0_i64;
    for (a, b) in points
        .iter()
        .zip(points.iter().cycle().skip(1))
        .take(points.len())
    {
        twice += i64::from(a.x) * i64::from(b.y) - i64::from(b.x) * i64::from(a.y);
    }
    twice.unsigned_abs() as f64 / 2.0
}

fn perimeter(points: &[imageproc::point::Point<i32>]) -> f64 {
    points
        .iter()
        .zip(points.iter().cycle().skip(1))
        .take(points.len())
        .map(|(a, b)| f64::from(a.x - b.x).hypot(f64::from(a.y - b.y)))
        .sum()
}

fn edge_support(edges: &GrayImage, x: u32, y: u32, w: u32, h: u32) -> f64 {
    let border = 6.min(((w.min(h) as f64 * 0.025) as u32).max(2));
    let mut count = 0_u32;
    for yy in y..y + h {
        for xx in x..x + w {
            let local_x = xx - x;
            let local_y = yy - y;
            if (local_x < border
                || local_y < border
                || local_x >= w - border
                || local_y >= h - border)
                && edges.get_pixel(xx, yy)[0] != 0
            {
                count += 1;
            }
        }
    }
    f64::from(count) / (2.0 * f64::from(w + h) * f64::from(border)).max(1.0)
}

fn near_duplicate(a: &Candidate, b: &Candidate) -> bool {
    a.x.abs_diff(b.x) <= 5
        && a.y.abs_diff(b.y) <= 5
        && a.width.abs_diff(b.width) <= 10
        && a.height.abs_diff(b.height) <= 10
}

fn detect(image: &RgbImage, args: &RegionArgs) -> Vec<Candidate> {
    let gray = image::DynamicImage::ImageRgb8(image.clone()).to_luma8();
    let low = canny(&gray, 24.0, 72.0);
    let high = canny(&gray, 48.0, 144.0);
    let mut edges = GrayImage::from_fn(gray.width(), gray.height(), |x, y| {
        image::Luma([low.get_pixel(x, y)[0] | high.get_pixel(x, y)[0]])
    });
    let horizontal = Mask::from_image(&GrayImage::from_pixel(7, 3, image::Luma([255])), 3, 1);
    let vertical = Mask::from_image(&GrayImage::from_pixel(3, 7, image::Luma([255])), 1, 3);
    for _ in 0..2 {
        edges = grayscale_close(&edges, &horizontal);
    }
    for _ in 0..2 {
        edges = grayscale_close(&edges, &vertical);
    }
    let mut candidates = Vec::new();
    let screen_area = f64::from(image.width()) * f64::from(image.height());
    for contour in find_contours::<i32>(&edges) {
        if contour.points.len() < 4 {
            continue;
        }
        let min_x = contour.points.iter().map(|p| p.x).min().unwrap_or(0).max(0) as u32;
        let max_x = contour.points.iter().map(|p| p.x).max().unwrap_or(0).max(0) as u32;
        let min_y = contour.points.iter().map(|p| p.y).min().unwrap_or(0).max(0) as u32;
        let max_y = contour.points.iter().map(|p| p.y).max().unwrap_or(0).max(0) as u32;
        let w = max_x - min_x + 1;
        let h = max_y - min_y + 1;
        if w < args.min_width
            || h < args.min_height
            || args.max_width.is_some_and(|max| w > max)
            || args.max_height.is_some_and(|max| h > max)
        {
            continue;
        }
        let area = f64::from(w) * f64::from(h);
        let area_ratio = area / screen_area;
        let aspect = f64::from(w) / f64::from(h);
        if !(0.0008..=0.80).contains(&area_ratio) || !(0.11..=9.0).contains(&aspect) {
            continue;
        }
        let rectangularity = polygon_area(&contour.points) / area;
        let length = perimeter(&contour.points);
        let vertices = approximate_polygon_dp(&contour.points, length * 0.02, true).len();
        if vertices > 14 {
            continue;
        }
        let support = edge_support(&edges, min_x, min_y, w, h);
        if rectangularity < 0.28 && support < 0.025 {
            continue;
        }
        let score = rectangularity * 2.0 + support * 4.0 + (area_ratio / 0.10).min(1.0) * 0.35
            - area_ratio * 0.35;
        let (radius, radius_confidence) = estimate_radius(image, min_x, min_y, w, h);
        candidates.push(Candidate {
            x: min_x,
            y: min_y,
            width: w,
            height: h,
            score,
            rectangularity,
            edge_support: support,
            area_ratio,
            vertices,
            radius,
            radius_confidence,
        });
    }
    candidates.sort_by_key(|r| u64::from(r.width) * u64::from(r.height));
    let mut deduped = Vec::new();
    for candidate in candidates {
        if !deduped.iter().any(|kept| near_duplicate(&candidate, kept)) {
            deduped.push(candidate);
        }
    }
    deduped
}

fn output(candidate: &Candidate, hyprctl: bool) -> Value {
    if hyprctl {
        json!({
            "at": [candidate.x, candidate.y],
            "size": [candidate.width, candidate.height],
            "score": candidate.score,
            "rectangularity": candidate.rectangularity,
            "edgeSupport": candidate.edge_support,
            "areaRatio": candidate.area_ratio,
            "vertices": candidate.vertices,
            "confidence": (candidate.score / 2.2).clamp(0.0, 1.0),
            "radius": candidate.radius,
            "radiusConfidence": candidate.radius_confidence,
            "shape": if candidate.radius >= 4.0 { "rounded-rect" } else { "rect" },
            "source": "contour",
        })
    } else {
        json!({
            "x": candidate.x, "y": candidate.y,
            "width": candidate.width, "height": candidate.height,
            "score": candidate.score, "rectangularity": candidate.rectangularity,
            "edge_support": candidate.edge_support, "area_ratio": candidate.area_ratio,
            "vertices": candidate.vertices, "corner_radius": candidate.radius,
            "corner_radius_confidence": candidate.radius_confidence,
        })
    }
}

pub fn run(args: &RegionArgs) -> Result<(), String> {
    let source = image_io::open(&args.image)?;
    if u64::from(source.width()) * u64::from(source.height()) > 20_000_000 {
        return Err("Contour input exceeds the 20 megapixel work limit".into());
    }
    let mut image = source.to_rgb8();
    let mut candidates = detect(&image, args);
    if args.single && !candidates.is_empty() {
        let best = candidates
            .iter()
            .max_by(|a, b| a.score.total_cmp(&b.score))
            .cloned()
            .unwrap();
        candidates = vec![best];
    }
    if let Some(path) = &args.debug_output {
        for region in &candidates {
            for offset in 0..2 {
                let rect = Rect::at(region.x as i32 + offset, region.y as i32 + offset).of_size(
                    region.width.saturating_sub(offset as u32 * 2),
                    region.height.saturating_sub(offset as u32 * 2),
                );
                draw_hollow_rect_mut(&mut image, rect, image::Rgb([255, 255, 255]));
            }
        }
        image
            .save(path)
            .map_err(|error| format!("Could not write debug image: {error}"))?;
    }
    let output: Vec<Value> = candidates
        .iter()
        .map(|candidate| output(candidate, args.hyprctl))
        .collect();
    println!("{}", json!(output));
    Ok(())
}
