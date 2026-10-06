#!/usr/bin/env python3

import argparse
import cv2
import json
import math
import sys

import numpy as np

DEFAULT_IMAGE_PATH = "/tmp/quickshell/media/screenshot/image"


# SNIP-ROUNDED-CONTENT-V5
def estimate_rounded_rect_radius(image, x, y, w, h):
    if w < 24 or h < 24:
        return 0.0, 0.0

    roi = image[y:y + h, x:x + w]
    if roi.size == 0:
        return 0.0, 0.0

    min_dim = min(w, h)
    if min_dim < 24:
        return 0.0, 0.0

    lab = cv2.cvtColor(
        roi,
        cv2.COLOR_BGR2LAB,
    ).astype(np.float32)

    inner = min(
        32,
        max(10, min_dim // 4),
    )
    patch_radius = max(
        2,
        min(4, min_dim // 20),
    )
    scan_depth = max(
        3,
        min(7, min_dim // 10),
    )
    scan_limit = max(
        10,
        min(64, min_dim // 2),
    )

    def median_patch(cx, cy, radius):
        x0 = max(0, int(cx - radius))
        x1 = min(w, int(cx + radius + 1))
        y0 = max(0, int(cy - radius))
        y1 = min(h, int(cy + radius + 1))

        patch = lab[y0:y1, x0:x1]
        if patch.size == 0:
            return None

        return np.median(
            patch.reshape(-1, 3),
            axis=0,
        )

    corners = {
        "tl": (2, 2, inner, inner, 1, 1),
        "tr": (w - 3, 2, w - 1 - inner, inner, -1, 1),
        "bl": (2, h - 3, inner, h - 1 - inner, 1, -1),
        "br": (w - 3, h - 3, w - 1 - inner, h - 1 - inner, -1, -1),
    }

    corner_estimates = []
    accepted_contrasts = []

    def transition_distance(
        pixels,
        outside_color,
        inside_color,
        contrast,
    ):
        tolerance = max(
            1.5,
            contrast * 0.05,
        )
        previous = -100

        for index, pixel in enumerate(pixels):
            distance_inside = float(
                np.linalg.norm(pixel - inside_color)
            )
            distance_outside = float(
                np.linalg.norm(pixel - outside_color)
            )

            if (
                distance_inside + tolerance
                < distance_outside
            ):
                if index == previous + 1:
                    return previous
                previous = index
            else:
                previous = -100

        return None

    def radius_from_arc_point(edge_gap, inward):
        return (
            edge_gap
            + inward
            + math.sqrt(
                max(
                    0.0,
                    2.0 * edge_gap * inward,
                )
            )
        )

    for (
        _name,
        (
            bg_x,
            bg_y,
            surface_x,
            surface_y,
            x_direction,
            y_direction,
        ),
    ) in corners.items():
        outside_color = median_patch(
            bg_x,
            bg_y,
            patch_radius,
        )
        inside_color = median_patch(
            surface_x,
            surface_y,
            patch_radius + 1,
        )

        if outside_color is None or inside_color is None:
            continue

        contrast = float(
            np.linalg.norm(
                outside_color - inside_color
            )
        )

        if contrast < 8.0:
            continue

        estimates = []

        for inward in range(1, scan_depth + 1):
            row_y = (
                inward
                if y_direction > 0
                else h - 1 - inward
            )

            row_pixels = np.asarray([
                lab[
                    row_y,
                    offset
                    if x_direction > 0
                    else w - 1 - offset,
                ]
                for offset in range(scan_limit)
            ])

            horizontal_gap = transition_distance(
                row_pixels,
                outside_color,
                inside_color,
                contrast,
            )

            if horizontal_gap is not None:
                estimates.append(
                    radius_from_arc_point(
                        horizontal_gap,
                        inward,
                    )
                )

            column_x = (
                inward
                if x_direction > 0
                else w - 1 - inward
            )

            column_pixels = np.asarray([
                lab[
                    offset
                    if y_direction > 0
                    else h - 1 - offset,
                    column_x,
                ]
                for offset in range(scan_limit)
            ])

            vertical_gap = transition_distance(
                column_pixels,
                outside_color,
                inside_color,
                contrast,
            )

            if vertical_gap is not None:
                estimates.append(
                    radius_from_arc_point(
                        vertical_gap,
                        inward,
                    )
                )

        if len(estimates) < 3:
            continue

        corner_radius = float(
            np.median(estimates)
        )

        if corner_radius < 3.0:
            continue

        corner_estimates.append(
            corner_radius
        )
        accepted_contrasts.append(
            contrast
        )

    if len(corner_estimates) < 3:
        return 0.0, 0.0

    radius = float(
        np.median(corner_estimates)
    )

    max_radius = min(
        64.0,
        min_dim * 0.45,
    )

    if radius < 4.0 or radius > max_radius:
        return 0.0, 0.0

    deviations = np.abs(
        np.asarray(corner_estimates) - radius
    )
    median_deviation = float(
        np.median(deviations)
    )

    consistency = max(
        0.0,
        1.0
        - median_deviation
        / max(2.0, radius * 0.35),
    )

    median_contrast = float(
        np.median(accepted_contrasts)
    )
    contrast_confidence = min(
        1.0,
        max(
            0.0,
            (median_contrast - 8.0) / 24.0,
        ),
    )

    confidence = (
        consistency * 0.55
        + contrast_confidence * 0.45
    )

    if confidence < 0.58:
        return 0.0, float(confidence)

    return (
        float(round(radius, 1)),
        float(round(confidence, 3)),
    )


def edge_support(edges, x, y, w, h):
    roi = edges[y:y + h, x:x + w]

    if roi.size == 0:
        return 0.0

    border = max(
        2,
        min(
            6,
            int(min(w, h) * 0.025),
        ),
    )

    band = roi.copy()

    if h > border * 2 and w > border * 2:
        band[
            border:h - border,
            border:w - border,
        ] = 0

    perimeter_band_area = max(
        1.0,
        2 * (w + h) * border,
    )

    return (
        float(cv2.countNonZero(band))
        / perimeter_band_area
    )


def near_duplicate(a, b):
    return (
        abs(a["x"] - b["x"]) <= 5
        and abs(a["y"] - b["y"]) <= 5
        and abs(a["width"] - b["width"]) <= 10
        and abs(a["height"] - b["height"]) <= 10
    )


def detect_regions(
    image_path,
    min_width,
    min_height,
    max_width=None,
    max_height=None,
):
    image = cv2.imread(image_path)

    if image is None:
        print(
            f"Error: Could not load image {image_path}",
            file=sys.stderr,
        )
        raise SystemExit(1)

    height, width = image.shape[:2]
    screen_area = width * height

    gray = cv2.cvtColor(
        image,
        cv2.COLOR_BGR2GRAY,
    )

    blurred = cv2.GaussianBlur(
        gray,
        (5, 5),
        0,
    )

    edges_low = cv2.Canny(
        blurred,
        24,
        72,
    )

    edges_high = cv2.Canny(
        blurred,
        48,
        144,
    )

    edges = cv2.bitwise_or(
        edges_low,
        edges_high,
    )

    kernel_h = cv2.getStructuringElement(
        cv2.MORPH_RECT,
        (7, 3),
    )

    kernel_v = cv2.getStructuringElement(
        cv2.MORPH_RECT,
        (3, 7),
    )

    edges = cv2.morphologyEx(
        edges,
        cv2.MORPH_CLOSE,
        kernel_h,
        iterations=2,
    )

    edges = cv2.morphologyEx(
        edges,
        cv2.MORPH_CLOSE,
        kernel_v,
        iterations=2,
    )

    contours, _ = cv2.findContours(
        edges,
        cv2.RETR_TREE,
        cv2.CHAIN_APPROX_SIMPLE,
    )

    candidates = []

    for contour in contours:
        x, y, w, h = cv2.boundingRect(contour)

        if w < min_width or h < min_height:
            continue

        if max_width is not None and w > max_width:
            continue

        if max_height is not None and h > max_height:
            continue

        area = w * h
        area_ratio = area / max(1, screen_area)

        if area_ratio < 0.0008 or area_ratio > 0.80:
            continue

        aspect = w / max(1, h)

        if aspect > 9.0 or aspect < 0.11:
            continue

        contour_area = abs(
            cv2.contourArea(contour)
        )

        rectangularity = (
            contour_area / max(1.0, area)
        )

        perimeter = cv2.arcLength(
            contour,
            True,
        )

        approx = (
            cv2.approxPolyDP(
                contour,
                0.02 * perimeter,
                True,
            )
            if perimeter > 0
            else contour
        )

        vertices = len(approx)

        if vertices > 14:
            continue

        support = edge_support(
            edges,
            x,
            y,
            w,
            h,
        )

        if (
            rectangularity < 0.28
            and support < 0.025
        ):
            continue

        score = (
            rectangularity * 2.0
            + support * 4.0
            + min(
                1.0,
                area_ratio / 0.10,
            ) * 0.35
            - area_ratio * 0.35
        )

        corner_radius, corner_radius_confidence = (
            estimate_rounded_rect_radius(
                image,
                x,
                y,
                w,
                h,
            )
        )

        candidates.append(
            {
                "x": int(x),
                "y": int(y),
                "width": int(w),
                "height": int(h),
                "score": float(score),
                "rectangularity": float(
                    rectangularity
                ),
                "edge_support": float(
                    support
                ),
                "area_ratio": float(area_ratio),
                "vertices": int(vertices),
                "corner_radius": float(corner_radius),
                "corner_radius_confidence": float(
                    corner_radius_confidence
                ),
            }
        )

    # Preserve nested rectangles, but remove near-identical duplicates.
    candidates.sort(
        key=lambda item: (
            item["width"] * item["height"]
        )
    )

    deduped = []

    for candidate in candidates:
        if any(
            near_duplicate(
                candidate,
                kept,
            )
            for kept in deduped
        ):
            continue

        deduped.append(candidate)

    return deduped, image


def draw_regions(image, regions, output_path):
    debug = image.copy()

    for region in regions:
        cv2.rectangle(
            debug,
            (
                region["x"],
                region["y"],
            ),
            (
                region["x"]
                + region["width"],
                region["y"]
                + region["height"],
            ),
            (255, 255, 255),
            2,
        )

    cv2.imwrite(
        output_path,
        debug,
    )


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Find logical rectangular UI regions "
            "using contour and edge analysis."
        )
    )

    parser.add_argument(
        "-i",
        "--image",
        default=DEFAULT_IMAGE_PATH,
    )

    parser.add_argument(
        "-do",
        "--debug-output",
    )

    parser.add_argument(
        "--min-width",
        type=int,
        default=90,
    )

    parser.add_argument(
        "--min-height",
        type=int,
        default=42,
    )

    parser.add_argument(
        "--max-width",
        type=int,
    )

    parser.add_argument(
        "--max-height",
        type=int,
    )

    parser.add_argument(
        "--single",
        action="store_true",
    )

    # Keep legacy options accepted so current QML / scripts do not break.
    parser.add_argument(
        "--quality",
        action="store_true",
    )

    parser.add_argument(
        "--k",
        type=int,
        default=3000,
    )

    parser.add_argument(
        "--min-size",
        type=int,
        default=50,
    )

    parser.add_argument(
        "--sigma",
        type=float,
        default=0.6,
    )

    parser.add_argument(
        "--resize-factor",
        type=float,
        default=1.0,
    )

    parser.add_argument(
        "--hyprctl",
        action="store_true",
    )

    args = parser.parse_args()

    regions, image = detect_regions(
        args.image,
        min_width=args.min_width,
        min_height=args.min_height,
        max_width=args.max_width,
        max_height=args.max_height,
    )

    if args.single and regions:
        regions = [
            max(
                regions,
                key=lambda r: r["score"],
            )
        ]

    if args.debug_output:
        draw_regions(
            image,
            regions,
            args.debug_output,
        )

    if args.hyprctl:
        output = [
            {
                "at": [
                    r["x"],
                    r["y"],
                ],
                "size": [
                    r["width"],
                    r["height"],
                ],
                "score": r["score"],
                "rectangularity": r["rectangularity"],
                "edgeSupport": r["edge_support"],
                "areaRatio": r["area_ratio"],
                "vertices": r["vertices"],
                "confidence": min(
                    1.0,
                    max(0.0, r["score"] / 2.2),
                ),
                "radius": r["corner_radius"],
                "radiusConfidence":
                    r["corner_radius_confidence"],
                "shape": (
                    "rounded-rect"
                    if r["corner_radius"] >= 4.0
                    else "rect"
                ),
                "source": "contour",
            }
            for r in regions
        ]
    else:
        output = regions

    print(
        json.dumps(output)
    )


if __name__ == "__main__":
    main()
