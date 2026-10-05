#!/usr/bin/env python3
"""Builds the AgentUX Plymouth theme's images into
files/usr/share/plymouth/themes/agentux/ (agentux.script draws them).

    cd plymouth && npm install && python3 build.py [--brand ../../agentux/brand]

Needs Node.js (for @resvg/resvg-js, the renderer the brand assets use) and
Pillow. The mark's geometry is the brand's (agentux brand/src/build.py); the
wordmark is the brand's svg/wordmark-mist.svg. Each image comes at 1x (for
1080p) and @2x (for 4K); agentux.script scales whichever is closer to the
screen. Edit this script, not the PNGs.

The animation is the wallpaper's motif, "messages on the bus": the mark sits
dimmed, and a short lit dash runs along each lane. The four start one after
the other (the outer lanes are longer) so that they reach the merge at the
same moment and leave along the line as one.
"""
import argparse
import io
import json
import math
import subprocess
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / "files/usr/share/plymouth/themes/agentux"

LIME = "#c6f36b"
MIST = "#e7eaef"
SLATE = "#949dab"
GRAPHITE = "#171b20"

# The mark, in its 64-unit box (brand/svg/mark-lime.svg).
LANES_Y = [13.0, 25.667, 38.333, 51.0]
LANE_W, TRUNK_W = 5.0, 6.0
MERGE = (38.0, 32.0)
TRUNK = (36.0, 56.0)  # the line starts under the lanes' ends
# The part of the box the mark covers, caps included, and its size at 1x:
# 2.4 px per unit, so the mark is 132 x 106 px on a 1080p screen.
VIEW = (5.0, 10.0, 55.0, 44.0)
PX_PER_UNIT = 2.4

# Animation: FRAMES frames at FPS (agentux.script plays them, then shows
# none for its pause), a lit dash DASH units long.
FPS = 25
FRAMES = 45
DASH = 11.0
COLUMNS = 9


def lane(y):
    return [(8.0, y), (24.5, y), (21.5, 32.0), MERGE]


def bezier(p, t):
    u = 1 - t
    return tuple(u**3 * a + 3 * u * u * t * b + 3 * u * t * t * c + t**3 * d
                 for a, b, c, d in zip(*p))


def split(p, t0, t1):
    """The part of cubic p between t0 and t1, as a cubic."""
    def at(q, t):
        a = [tuple(x + (y - x) * t for x, y in zip(q[i], q[i + 1])) for i in range(3)]
        b = [tuple(x + (y - x) * t for x, y in zip(a[i], a[i + 1])) for i in range(2)]
        c = tuple(x + (y - x) * t for x, y in zip(b[0], b[1]))
        return [q[0], a[0], b[0], c], [c, b[1], a[2], q[3]]
    _, right = at(p, t0)
    if t1 >= 1:
        return right
    left, _ = at(right, (t1 - t0) / (1 - t0))
    return left


class Arc:
    """Arc-length parametrisation of a cubic."""
    def __init__(self, p, n=4000):
        self.p = p
        self.ts = [i / n for i in range(n + 1)]
        pts = [bezier(p, t) for t in self.ts]
        self.s = [0.0]
        for a, b in zip(pts, pts[1:]):
            self.s.append(self.s[-1] + math.dist(a, b))
        self.length = self.s[-1]

    def t(self, s):
        s = min(max(s, 0.0), self.length)
        lo, hi = 0, len(self.s) - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            lo, hi = (mid, hi) if self.s[mid] <= s else (lo, mid)
        span = self.s[hi] - self.s[lo] or 1
        return self.ts[lo] + (self.ts[hi] - self.ts[lo]) * (s - self.s[lo]) / span


def cubic_d(p):
    (a, b), (c, d), (e, f), (g, h) = p
    return f"M{a:.3f} {b:.3f}C{c:.3f} {d:.3f} {e:.3f} {f:.3f} {g:.3f} {h:.3f}"


def svg(body, w, h, view=VIEW):
    x, y, vw, vh = view
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
            f'viewBox="{x} {y} {vw} {vh}"><g fill="none" stroke-linecap="round">{body}</g></svg>')


def mark_body(color=LIME):
    lanes = " ".join(f"M8 {y:.3f}C24.50 {y:.3f} 21.50 32 38 32" for y in LANES_Y)
    return (f'<path stroke="{color}" stroke-width="{LANE_W}" d="{lanes}"/>'
            f'<path stroke="{color}" stroke-width="{TRUNK_W}" d="M{TRUNK[0]} 32H{TRUNK[1]}"/>')


def ease(u):
    # Slower at both ends, never stopping: the dashes ease in and settle out.
    return u - 0.5 / (2 * math.pi) * math.sin(2 * math.pi * u)


def dash_body(frame):
    """The lit parts of the mark in one frame."""
    arcs = [Arc(lane(y)) for y in LANES_Y]
    longest = max(a.length for a in arcs)
    trunk_len = TRUNK[1] - MERGE[0]
    # Head position along lane + line: the longest lane's dash enters at the
    # start, every dash reaches the merge at the same time, and the merged
    # one has left the line by the last frame.
    speed = longest + trunk_len + DASH
    tau = ease(frame / (FRAMES - 1))
    parts = []
    for arc in arcs:
        head = arc.length + speed * tau - longest
        a, b = max(head - DASH, 0.0), min(head, arc.length)
        if b > a + 1e-3:
            parts.append(f'<path stroke="{LIME}" stroke-width="{LANE_W}" '
                         f'd="{cubic_d(split(arc.p, arc.t(a), arc.t(b)))}"/>')
    # All four are on the line together, so one dash stands for them.
    head = speed * tau - longest
    a, b = max(head - DASH, 0.0), min(head, trunk_len)
    if b > a + 1e-3:
        x0 = MERGE[0] + a
        parts.append(f'<path stroke="{LIME}" stroke-width="{TRUNK_W}" '
                     f'd="M{x0:.3f} 32H{MERGE[0] + b:.3f}"/>')
    return "".join(parts)


def rounded_rect(w, h, r, fill, stroke=None, stroke_opacity=1.0):
    s = (f' stroke="{stroke}" stroke-opacity="{stroke_opacity}" stroke-width="2"'
         if stroke else "")
    inset = 1 if stroke else 0
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'
            f'<rect x="{inset}" y="{inset}" width="{w - 2 * inset}" height="{h - 2 * inset}" '
            f'rx="{r}" fill="{fill}"{s}/></svg>')


def render(jobs):
    subprocess.run(["node", str(HERE / "render.mjs")], input=json.dumps(jobs).encode(),
                   check=True, cwd=HERE)


def optimise(path):
    """Re-save as a palette PNG (lossless here: few colours) to keep it small."""
    im = Image.open(path).convert("RGBA")
    colours = im.getcolors(256)
    if colours is not None:
        q = im.quantize(colors=len(colours), method=Image.Quantize.FASTOCTREE)
        if q.convert("RGBA").tobytes() == im.tobytes():
            im = q
    buf = io.BytesIO()
    im.save(buf, "PNG", optimize=True)
    path.write_bytes(buf.getvalue())


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--brand", type=Path, default=HERE.parent.parent / "agentux/brand",
                    help="the agentux repository's brand/ directory")
    args = ap.parse_args()
    wordmark = args.brand / "svg/wordmark-mist.svg"
    if not wordmark.is_file():
        sys.exit(f"{wordmark} not found; pass --brand")
    wm_svg = wordmark.read_text()
    tmp = HERE / ".build"
    tmp.mkdir(exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)

    jobs = []
    for scale, suffix in ((1, ""), (2, "@2x")):
        w, h = round(VIEW[2] * PX_PER_UNIT * scale), round(VIEW[3] * PX_PER_UNIT * scale)
        jobs.append({"svg": svg(mark_body(), w, h), "out": str(OUT / f"mark{suffix}.png")})
        for f in range(FRAMES):
            jobs.append({"svg": svg(dash_body(f), w, h), "out": str(tmp / f"dash{suffix}-{f:02d}.png")})
        # Wordmark: 120 px wide at 1x, its own aspect ratio.
        wm_w = 120 * scale
        wm = wm_svg.replace('width="463.04" height="101.92"',
                            f'width="{wm_w}" height="{round(wm_w * 101.92 / 463.04)}"', 1)
        assert wm != wm_svg, "wordmark-mist.svg changed size; update build.py"
        jobs.append({"svg": wm, "out": str(OUT / f"wordmark{suffix}.png")})
    # Shapes that scale cleanly: drawn once at 2x.
    jobs += [
        # Passphrase field: Graphite, a quiet Slate edge.
        {"svg": rounded_rect(640, 88, 16, GRAPHITE, SLATE, 0.28), "out": str(OUT / "entry.png")},
        {"svg": ('<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20">'
                 f'<circle cx="10" cy="10" r="10" fill="{LIME}"/></svg>'), "out": str(OUT / "bullet.png")},
        # Progress: a Lime hairline on a Graphite one; round ends.
        {"svg": rounded_rect(400, 4, 2, GRAPHITE), "out": str(OUT / "track.png")},
        {"svg": rounded_rect(400, 4, 2, LIME), "out": str(OUT / "fill.png")},
    ]
    render(jobs)

    # Frames go into one sheet per scale (agentux.script crops them), COLUMNS wide.
    for suffix in ("", "@2x"):
        frames = [Image.open(tmp / f"dash{suffix}-{f:02d}.png") for f in range(FRAMES)]
        fw, fh = frames[0].size
        rows = math.ceil(FRAMES / COLUMNS)
        sheet = Image.new("RGBA", (fw * COLUMNS, fh * rows))
        for i, im in enumerate(frames):
            sheet.paste(im, ((i % COLUMNS) * fw, (i // COLUMNS) * fh))
        sheet.save(OUT / f"dashes{suffix}.png")
    script = (OUT / "agentux.script").read_text()
    for name, value in (("FRAMES", FRAMES), ("COLUMNS", COLUMNS)):
        if f"\n{name} = {value};" not in script:
            sys.exit(f"agentux.script must say {name} = {value}; to match the sheets")
    for p in sorted(OUT.glob("*.png")):
        optimise(p)
        print(f"{p.relative_to(HERE.parent)}  {p.stat().st_size} bytes")
    for p in tmp.glob("*.png"):
        p.unlink()
    tmp.rmdir()


if __name__ == "__main__":
    main()
