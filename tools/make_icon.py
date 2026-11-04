"""Draws the TinserBox icon: a golden waveform inside an open music box on dark forest green.

Writes icon.png (256x256) and icon.ico (16-256 px) to the project root. Each size is drawn
separately at 8x and downsampled, with stroke widths kept at least ~1 px so 16x16 stays legible.
"""
import math
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GOLD = (236, 196, 112)
GOLD_DARK = (176, 128, 58)
BG_TOP = (18, 42, 30)
BG_BOTTOM = (4, 10, 7)


def draw(size: int) -> Image.Image:
    ss = 8
    s = size * ss
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    # Background: rounded square with vertical forest-green to black gradient.
    grad = Image.new("RGBA", (s, s))
    gd = ImageDraw.Draw(grad)
    for y in range(s):
        t = y / (s - 1)
        gd.line([(0, y), (s, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)) + (255,))
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * 0.2), fill=255)
    img.paste(grad, (0, 0), mask)

    d = ImageDraw.Draw(img)
    stroke = max(s * 0.045, ss * 1.1)
    small = size <= 24
    # Music box body and open lid.
    left, right = (s * 0.09, s * 0.91) if small else (s * 0.17, s * 0.83)
    top, bottom = (s * 0.42, s * 0.88) if small else (s * 0.50, s * 0.82)
    d.rounded_rectangle([left, top, right, bottom], radius=s * 0.04, outline=GOLD, width=int(stroke))
    lid_h = s * (0.16 if small else 0.2)
    d.polygon([(left, top), (right, top), (right - s * 0.08, top - lid_h), (left + s * 0.08, top - lid_h)],
              outline=GOLD_DARK, width=int(stroke * 0.8))
    if not small:
        # Winding key on the side.
        kx, ky = right + stroke * 0.5, (top + bottom) / 2
        d.line([(kx, ky), (kx + s * 0.06, ky)], fill=GOLD, width=int(stroke * 0.8))
        d.ellipse([kx + s * 0.05, ky - s * 0.04, kx + s * 0.11, ky + s * 0.04], outline=GOLD, width=int(stroke * 0.7))
    # Waveform inside the box.
    cy = (top + bottom) / 2
    amp = (bottom - top) * (0.22 if small else 0.28)
    x0, x1 = left + stroke * 1.9, right - stroke * 1.9
    pts = []
    for i in range(121):
        p = i / 120
        env = math.sin(p * math.pi)
        y = cy - math.sin(p * math.tau * (1.0 if small else 2.5)) * amp * env
        pts.append((x0 + (x1 - x0) * p, y))
    d.line(pts, fill=GOLD, width=int(stroke * (0.9 if small else 0.75)), joint="curve")
    if not small:
        # Two notes rising from the open lid.
        for nx, ny, r in [(0.42, 0.22, 0.045), (0.6, 0.15, 0.04)]:
            cx, cyn, rr = s * nx, s * ny, s * r
            d.ellipse([cx - rr * 1.2, cyn - rr, cx + rr * 1.2, cyn + rr], fill=GOLD)
            d.line([(cx + rr * 1.1, cyn), (cx + rr * 1.1, cyn - s * 0.13)], fill=GOLD, width=int(stroke * 0.6))
    return img.resize((size, size), Image.LANCZOS)


if __name__ == "__main__":
    sizes = [16, 24, 32, 48, 64, 128, 256]
    images = {n: draw(n) for n in sizes}
    images[256].save(os.path.join(ROOT, "icon.png"))
    images[256].save(os.path.join(ROOT, "icon.ico"), sizes=[(n, n) for n in sizes],
                     append_images=[images[n] for n in sizes[:-1]])
    preview = Image.new("RGBA", (16 + 32 + 256 + 40, 256), (40, 40, 40, 255))
    preview.paste(images[16], (0, 0), images[16]); preview.paste(images[32], (26, 0), images[32])
    preview.paste(images[256], (68, 0), images[256])
    if os.environ.get("ICON_PREVIEW"):
        preview.save(os.environ["ICON_PREVIEW"])
