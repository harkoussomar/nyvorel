#!/usr/bin/env python3
import math
import statistics
import sys

from PIL import Image

# Allowed scheme types
SCHEMES = [
    "scheme-content",
    "scheme-expressive",
    "scheme-fidelity",
    "scheme-fruit-salad",
    "scheme-monochrome",
    "scheme-neutral",
    "scheme-rainbow",
    "scheme-tonal-spot"
]

def image_colorfulness(image):
    # Based on Hasler and Süsstrunk's colorfulness metric
    pixels = list(image.get_flattened_data() if hasattr(image, "get_flattened_data") else image.getdata())
    rg = [abs(r - g) for r, g, _ in pixels]
    yb = [abs(0.5 * (r + g) - b) for r, g, b in pixels]
    std_rg = statistics.pstdev(rg)
    std_yb = statistics.pstdev(yb)
    mean_rg = statistics.fmean(rg)
    mean_yb = statistics.fmean(yb)
    colorfulness = math.hypot(std_rg, std_yb) + 0.3 * math.hypot(mean_rg, mean_yb)
    return colorfulness

# scheme-content respects the image's colors very well, but it might
# look too saturated, so we only use it for not very colorful images to be safe
def pick_scheme(colorfulness):
    if colorfulness < 40:
        return "scheme-neutral"
    else:
        return "scheme-tonal-spot"

def load_and_resize_image(img_path, max_dim=128):
    try:
        img = Image.open(img_path).convert("RGB")
    except (OSError, ValueError):
        return None
    w, h = img.size
    if max(h, w) > max_dim:
        scale = max_dim / max(h, w)
        img = img.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.Resampling.BOX)
    return img

def main():
    colorfulness_mode = False
    args = sys.argv[1:]
    if '--colorfulness' in args:
        colorfulness_mode = True
        args.remove('--colorfulness')
    if len(args) < 1:
        print("scheme-tonal-spot")
        sys.exit(1)
    img_path = args[0]
    img = load_and_resize_image(img_path)
    if img is None:
        print("scheme-tonal-spot")
        sys.exit(1)
    colorfulness = image_colorfulness(img)
    if colorfulness_mode:
        print(f"{colorfulness}")
    else:
        scheme = pick_scheme(colorfulness)
        print(scheme)

if __name__ == "__main__":
    main()
