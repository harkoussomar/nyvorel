#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

from PIL import Image
from materialyoucolor.hct import Hct
from materialyoucolor.score.score import Score
from materialyoucolor.utils.color_utils import rgba_from_argb

try:
    from materialyoucolor.quantize import ImageQuantizeCelebi
except Exception:
    ImageQuantizeCelebi = None

from materialyoucolor.quantize import QuantizeCelebi
from materialyoucolor.dynamiccolor.material_dynamic_colors import MaterialDynamicColors


# Roles used by Nyvorel's Matugen colors.json template.
ROLE_NAMES = [
    "background",
    "error",
    "error_container",
    "inverse_on_surface",
    "inverse_primary",
    "inverse_surface",
    "on_background",
    "on_error",
    "on_error_container",
    "on_primary",
    "on_primary_container",
    "on_primary_fixed",
    "on_primary_fixed_variant",
    "on_secondary",
    "on_secondary_container",
    "on_secondary_fixed",
    "on_secondary_fixed_variant",
    "on_surface",
    "on_surface_variant",
    "on_tertiary",
    "on_tertiary_container",
    "on_tertiary_fixed",
    "on_tertiary_fixed_variant",
    "outline",
    "outline_variant",
    "primary",
    "primary_container",
    "primary_fixed",
    "primary_fixed_dim",
    "scrim",
    "secondary",
    "secondary_container",
    "secondary_fixed",
    "secondary_fixed_dim",
    "shadow",
    "surface",
    "surface_bright",
    "surface_container",
    "surface_container_high",
    "surface_container_highest",
    "surface_container_low",
    "surface_container_lowest",
    "surface_dim",
    "surface_tint",
    "surface_variant",
    "tertiary",
    "tertiary_container",
    "tertiary_fixed",
    "tertiary_fixed_dim",
]


def argb_hex(argb: int) -> str:
    r, g, b, _ = rgba_from_argb(argb)
    return f"#{round(r):02x}{round(g):02x}{round(b):02x}"


def rgba_hex(rgba: Any) -> str:
    values = list(rgba)
    if len(values) < 3:
        raise RuntimeError(f"Invalid RGBA value: {rgba!r}")
    r, g, b = values[:3]
    if max(float(r), float(g), float(b)) <= 1.0:
        r, g, b = float(r) * 255, float(g) * 255, float(b) * 255
    return f"#{round(float(r)):02x}{round(float(g)):02x}{round(float(b)):02x}"


def normalized_hex(value: str) -> str:
    value = str(value).strip()
    if not value.startswith("#"):
        value = "#" + value
    if len(value) == 9:  # #RRGGBBAA
        value = value[:7]
    if len(value) != 7:
        raise RuntimeError(f"Invalid hex color: {value!r}")
    int(value[1:], 16)
    return value.lower()


def _camel(name: str) -> str:
    parts = name.split("_")
    return parts[0] + "".join(part[:1].upper() + part[1:] for part in parts[1:])


def source_from_image(path: str) -> str:
    image_path = Path(path)
    if not image_path.is_file():
        raise RuntimeError(f"Image not found: {image_path}")

    # Current materialyoucolor ships a C++ path-based quantizer. Prefer it when
    # available because it is both faster and more memory-efficient.
    if ImageQuantizeCelebi is not None:
        try:
            result = ImageQuantizeCelebi(str(image_path), 5, 128)
            scored = Score.score(result)
            if scored:
                return argb_hex(scored[0])
        except Exception:
            pass

    # Compatibility path for older II environments.
    image = Image.open(image_path)
    if image.format == "GIF":
        try:
            image.seek(1)
        except EOFError:
            image.seek(0)
    image = image.convert("RGB")
    image.thumbnail((128, 128), Image.Resampling.BICUBIC)
    pixels = list(image.getdata())
    colors = QuantizeCelebi(pixels, 128)
    scored = Score.score(colors)
    if not scored:
        raise RuntimeError("No source-color candidates were produced for the image")
    return argb_hex(scored[0])


def scheme_class(name: str):
    if name == "scheme-fruit-salad":
        from materialyoucolor.scheme.scheme_fruit_salad import SchemeFruitSalad as Scheme
    elif name == "scheme-expressive":
        from materialyoucolor.scheme.scheme_expressive import SchemeExpressive as Scheme
    elif name == "scheme-monochrome":
        from materialyoucolor.scheme.scheme_monochrome import SchemeMonochrome as Scheme
    elif name == "scheme-rainbow":
        from materialyoucolor.scheme.scheme_rainbow import SchemeRainbow as Scheme
    elif name == "scheme-neutral":
        from materialyoucolor.scheme.scheme_neutral import SchemeNeutral as Scheme
    elif name == "scheme-fidelity":
        from materialyoucolor.scheme.scheme_fidelity import SchemeFidelity as Scheme
    elif name == "scheme-content":
        from materialyoucolor.scheme.scheme_content import SchemeContent as Scheme
    else:
        from materialyoucolor.scheme.scheme_tonal_spot import SchemeTonalSpot as Scheme
    return Scheme


def _make_scheme(Scheme, hct, dark: bool):
    attempts = [
        lambda: Scheme(hct, dark, 0.0, spec_version="2025"),
        lambda: Scheme(hct, dark, 0.0),
        lambda: Scheme(source_color_hct=hct, is_dark=dark, contrast_level=0.0, spec_version="2025"),
        lambda: Scheme(source_color_hct=hct, is_dark=dark, contrast_level=0.0),
    ]
    errors: list[str] = []
    for build in attempts:
        try:
            return build()
        except (TypeError, ValueError) as exc:
            errors.append(str(exc))
    raise RuntimeError("Could not construct Material scheme: " + " | ".join(errors[-2:]))


def _providers():
    # materialyoucolor v3 / Material 2025.
    try:
        yield MaterialDynamicColors(spec="2025")
    except Exception:
        pass
    # Earlier v3 snapshots and stable v2.
    try:
        yield MaterialDynamicColors()
    except Exception:
        pass
    yield MaterialDynamicColors


def _role_object(name: str):
    candidates = [name, _camel(name)]
    # A few package versions kept old Material role spellings.
    aliases = {
        "surface_tint": ["surfaceTint"],
        "surface_variant": ["surfaceVariant"],
        "on_surface_variant": ["onSurfaceVariant"],
    }
    candidates.extend(aliases.get(name, []))

    for provider in _providers():
        for candidate in candidates:
            try:
                role = getattr(provider, candidate)
            except Exception:
                continue

            # Some revisions expose zero-argument factories on the provider.
            if callable(role) and not any(
                hasattr(role, attr) for attr in ("get_hex", "get_rgba", "get_argb", "get_hct")
            ):
                try:
                    role = role()
                except TypeError:
                    pass

            if any(hasattr(role, attr) for attr in ("get_hex", "get_rgba", "get_argb", "get_hct")):
                return role

    raise RuntimeError(f"Material dynamic color role is unavailable: {name}")


def _role_hex(role, scheme) -> str:
    if hasattr(role, "get_hex"):
        try:
            return normalized_hex(role.get_hex(scheme))
        except Exception:
            pass
    if hasattr(role, "get_rgba"):
        try:
            return rgba_hex(role.get_rgba(scheme))
        except Exception:
            pass
    if hasattr(role, "get_argb"):
        try:
            return argb_hex(role.get_argb(scheme))
        except Exception:
            pass
    if hasattr(role, "get_hct"):
        try:
            hct = role.get_hct(scheme)
            if hasattr(hct, "to_int"):
                return argb_hex(hct.to_int())
            if hasattr(hct, "to_rgba"):
                return rgba_hex(hct.to_rgba())
        except Exception:
            pass
    raise RuntimeError("Unsupported materialyoucolor DynamicColor API")


def full_palette(seed: str, scheme_name: str, mode: str) -> dict[str, str]:
    value = seed.lstrip("#")
    if len(value) != 6:
        raise RuntimeError(f"Invalid seed color: {seed!r}")
    argb = 0xFF000000 | int(value, 16)
    hct = Hct.from_int(argb)
    Scheme = scheme_class(scheme_name)
    scheme = _make_scheme(Scheme, hct, mode == "dark")

    colors: dict[str, str] = {}
    failures: list[str] = []
    for role_name in ROLE_NAMES:
        try:
            colors[role_name] = _role_hex(_role_object(role_name), scheme)
        except Exception as exc:
            failures.append(f"{role_name}: {exc}")

    # A full preview palette must be complete enough to replace Matugen's
    # colors.json. Do not silently render a partial fake palette.
    required = {
        "background", "on_background", "surface", "on_surface",
        "primary", "on_primary", "primary_container", "on_primary_container",
        "secondary", "secondary_container", "tertiary", "tertiary_container",
        "outline", "outline_variant",
    }
    missing = sorted(required.difference(colors))
    if missing:
        detail = "; ".join(failures[:6])
        raise RuntimeError(f"Material palette is incomplete; missing {', '.join(missing)}. {detail}")
    return colors


def variant_preview(seed: str, scheme_name: str, mode: str) -> dict[str, str]:
    full = full_palette(seed, scheme_name, mode)
    return {
        "primary": full["primary"],
        "secondary": full["secondary"],
        "tertiary": full["tertiary"],
        "surface": full["surface_container"],
        "onSurface": full["on_surface"],
    }


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit(2)

    command = sys.argv[1]
    if command == "source":
        print(source_from_image(sys.argv[2]))
        return

    if command == "variants":
        if len(sys.argv) < 5:
            raise SystemExit(2)
        seed, mode = sys.argv[2], sys.argv[3]
        result = []
        for scheme_name in sys.argv[4:]:
            result.append({"id": scheme_name, "colors": variant_preview(seed, scheme_name, mode)})
        print(json.dumps(result))
        return

    if command == "full":
        if len(sys.argv) != 5:
            raise SystemExit(2)
        seed, mode, scheme_name = sys.argv[2], sys.argv[3], sys.argv[4]
        print(json.dumps(full_palette(seed, scheme_name, mode)))
        return

    raise SystemExit(2)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"palette_probe: {exc}", file=sys.stderr)
        raise SystemExit(1)
