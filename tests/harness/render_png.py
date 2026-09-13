#!/usr/bin/env python3
"""Rasterize the DrawingImmediate calls recorded by a harness run (JSON: lines) into a PNG with Pillow.

usage: render_png.py run.out.txt out.png [x0,y0,x1,y1]
Text is drawn one character per advance with the same monospace metrics the harness used for layout.
"""
import json
import os
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFont

FONT_CACHE: dict[int, ImageFont.ImageFont] = {}


def font(size: int):
    if size not in FONT_CACHE:
        loaded = None
        for name in ("consola.ttf", "DejaVuSansMono.ttf", "cour.ttf"):
            try:
                loaded = ImageFont.truetype(name, size)
                break
            except OSError:
                continue
        FONT_CACHE[size] = loaded or ImageFont.load_default()
    return FONT_CACHE[size]


def rgba(r, g, b, a):
    return (int(r), int(g), int(b), max(0, min(255, round(a * 255))))


def composite_polygon(base: Image.Image, points, color) -> None:
    xs, ys = [p[0] for p in points], [p[1] for p in points]
    x0, y0 = int(min(xs)), int(min(ys))
    x1, y1 = int(max(xs)) + 2, int(max(ys)) + 2
    if x1 <= x0 or y1 <= y0:
        return
    layer = Image.new("RGBA", (x1 - x0, y1 - y0), (0, 0, 0, 0))
    ImageDraw.Draw(layer).polygon([(x - x0, y - y0) for x, y in points], fill=color)
    base.alpha_composite(layer, dest=(x0, y0))


def main() -> None:
    src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    crop = tuple(int(v) for v in sys.argv[3].split(",")) if len(sys.argv) > 3 else None
    width, height, frames = 1280, 800, []
    for line in src.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("SIZE:"):
            width, height = (int(v) for v in line[5:].split("x"))
        elif line.startswith("JSON:"):
            frames.append(json.loads(line[5:]))
    _, calls = frames[int(os.environ.get("FRAME", "-1"))]  # FRAME=0 picks the first recorded frame

    base = Image.new("RGBA", (width, height))
    backdrop = ImageDraw.Draw(base)
    top, bottom = (111, 167, 214), (47, 79, 47)
    for y in range(height):
        t = y / max(1, height - 1)
        backdrop.line([(0, y), (width, y)], fill=tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,))

    for call in calls:
        kind = call[0]
        if kind == "rect":
            x, y, w, h = call[1:5]
            x0, y0, x1, y1 = round(x), round(y), round(x + w), round(y + h)
            rounding = call[9] if len(call) > 9 else 0
            if x1 > x0 and y1 > y0 and x0 >= 0 and y0 >= 0:
                if rounding > 0:
                    layer = Image.new("RGBA", (x1 - x0, y1 - y0), (0, 0, 0, 0))
                    ImageDraw.Draw(layer).rounded_rectangle((0, 0, x1 - x0 - 1, y1 - y0 - 1), radius=rounding, fill=rgba(*call[5:9]))
                else:
                    layer = Image.new("RGBA", (x1 - x0, y1 - y0), rgba(*call[5:9]))
                base.alpha_composite(layer, dest=(x0, y0))
        elif kind == "circle":
            cx, cy, r = call[1:4]
            x0, y0 = int(cx - r) - 1, int(cy - r) - 1
            size = int(r * 2) + 4
            if x0 >= 0 and y0 >= 0 and size > 0:
                layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
                ImageDraw.Draw(layer).ellipse((cx - r - x0, cy - r - y0, cx + r - x0, cy + r - y0), fill=rgba(*call[4:8]))
                base.alpha_composite(layer, dest=(x0, y0))
        elif kind == "quad":
            composite_polygon(base, [(call[1], call[2]), (call[3], call[4]), (call[5], call[6]), (call[7], call[8])], rgba(*call[9:13]))
        elif kind == "tri":
            composite_polygon(base, [(call[1], call[2]), (call[3], call[4]), (call[5], call[6])], rgba(*call[7:11]))
        elif kind == "text":
            x, y, size = call[1], call[2], int(call[4])
            text = call[9]
            advance = int(size * 0.55 + 0.5)
            layer = Image.new("RGBA", (max(1, advance * len(text) + size), size + 6), (0, 0, 0, 0))
            draw = ImageDraw.Draw(layer)
            face = font(size)
            color = rgba(*call[5:9])
            for i, ch in enumerate(text):
                draw.text((i * advance, 1), ch, font=face, fill=color)
            base.alpha_composite(layer, dest=(round(x), round(y)))

    image = base.convert("RGB")
    if crop:
        image = image.crop(crop)
    dst.parent.mkdir(parents=True, exist_ok=True)
    image.save(dst)
    print(f"wrote {dst} ({image.width}x{image.height}, {len(calls)} calls)")


if __name__ == "__main__":
    main()
