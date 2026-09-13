#!/usr/bin/env python3
"""Render recorded DrawingImmediate calls (JSON: lines from a harness run) onto HTML canvases."""
import json
import pathlib
import sys

TEMPLATE = """<!doctype html>
<meta charset="utf-8">
<title>DrawingImmediate replay</title>
<style>
  body { margin: 0; background: #0b0f14; color: #cfd8e3; font: 13px system-ui, sans-serif; }
  figure { margin: 16px; }
  figcaption { margin-bottom: 6px; }
  canvas { display: block; background: #3b5a78; }
</style>
<body>
<script>
const FRAMES = __DATA__;
const W = __W__, H = __H__;
const ADVANCE = size => Math.floor(size * 0.55 + 0.5);  // same metrics as the harness MeasureText
const rgba = (r, g, b, a) => `rgba(${r},${g},${b},${a})`;
for (const [label, calls] of FRAMES) {
  const fig = document.createElement('figure');
  const cap = document.createElement('figcaption');
  cap.textContent = `${label} - ${calls.length} DrawingImmediate calls`;
  const canvas = document.createElement('canvas');
  canvas.width = W; canvas.height = H;
  fig.append(cap, canvas); document.body.append(fig);
  const g = canvas.getContext('2d');
  // a fake "game" backdrop so transparency is visible
  const grad = g.createLinearGradient(0, 0, 0, H); grad.addColorStop(0, '#6fa7d6'); grad.addColorStop(1, '#2f4f2f');
  g.fillStyle = grad; g.fillRect(0, 0, W, H);
  for (const c of calls) {
    const kind = c[0];
    if (kind === 'rect') {
      g.fillStyle = rgba(c[5], c[6], c[7], c[8]);
      if (c[9] > 0) { g.beginPath(); g.roundRect(c[1], c[2], c[3], c[4], c[9]); g.fill(); } else { g.fillRect(c[1], c[2], c[3], c[4]); }
    } else if (kind === 'circle') {
      g.fillStyle = rgba(c[4], c[5], c[6], c[7]);
      g.beginPath(); g.arc(c[1], c[2], c[3], 0, Math.PI * 2); g.fill();
    } else if (kind === 'quad') {
      g.fillStyle = rgba(c[9], c[10], c[11], c[12]);
      g.beginPath(); g.moveTo(c[1], c[2]); g.lineTo(c[3], c[4]); g.lineTo(c[5], c[6]); g.lineTo(c[7], c[8]); g.closePath(); g.fill();
    } else if (kind === 'tri') {
      g.fillStyle = rgba(c[7], c[8], c[9], c[10]);
      g.beginPath(); g.moveTo(c[1], c[2]); g.lineTo(c[3], c[4]); g.lineTo(c[5], c[6]); g.closePath(); g.fill();
    } else if (kind === 'text') {
      const size = c[4];
      g.fillStyle = rgba(c[5], c[6], c[7], c[8]);
      g.font = `${size}px Consolas, "Courier New", monospace`;
      g.textBaseline = 'top';
      const adv = ADVANCE(size);
      let x = c[1];
      for (const ch of c[9]) { g.fillText(ch, x, c[2] + 1); x += adv; }
    }
  }
}
</script>
"""


def write_viewer(src: pathlib.Path, dst: pathlib.Path) -> int:
    width, height = 1280, 800
    frames = []
    for line in src.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("JSON:"):
            frames.append(json.loads(line[5:]))
        elif line.startswith("SIZE:"):
            width, height = (int(v) for v in line[5:].split("x"))
    html = TEMPLATE.replace("__DATA__", json.dumps(frames)).replace("__W__", str(width)).replace("__H__", str(height))
    dst.write_text(html, encoding="utf-8")
    return len(frames)


def main() -> None:
    src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    print(f"viewer: {dst} ({write_viewer(src, dst)} frame(s))")


if __name__ == "__main__":
    main()
