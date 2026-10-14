#!/usr/bin/env python3
"""Builds the AgentUX Plymouth theme's images into
files/usr/share/plymouth/themes/agentux/ (agentux.script draws them).

    cd plymouth && npm install && python3 build.py [--brand ../../agentux/brand]

Needs Node.js (for @resvg/resvg-js, the renderer the brand assets use) and
Pillow. The mark is the brand's swimming penguin, split into the named parts
of its traced geometry (brand/src/penguin.svg in the agentux repository: the
same parts, wake opacity and wake-to-back gradient as brand/src/build.py's
mark); the wordmark is the brand's svg/wordmark-mist.svg. Each image comes at
1x (for 1080p) and @2x (for 4K); agentux.script scales whichever is closer to
the screen. Edit this script, not the PNGs.

The animation: the penguin swims in place. agentux.script bobs it up and
down, pitches it with the bob and strokes its flipper, a sprite of its own
turning around its root; the wake streams backwards (a sprite sheet: the
water lines with a brighter swell scrolling left through them, a seamless
loop); bubbles rise from where the wake leaves the penguin's back, drift
back and fade. This script writes the parts and the sheet, and the geometry
the script needs (pivots, offsets, bubble spawn points, in 1080p pixels from
the mark's top-left corner) into agentux.script's constants block, so the
two cannot drift apart.
"""
import argparse
import io
import json
import math
import re
import subprocess
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / "files/usr/share/plymouth/themes/agentux"
SCRIPT = OUT / "agentux.script"

LIME = "#c6f36b"
MIST = "#e7eaef"
SLATE = "#949dab"
GRAPHITE = "#171b20"

# The mark, as the brand draws it (brand/src/build.py): the wake at WAKE
# opacity, and a gradient (x RAMP, art units) carrying the middle water line
# into the penguin's back; WING keeps the wing out of that gradient.
WAKE = 0.42
RAMP = (560.0, 700.0)
WING = (560.0, 380.0, 960.0, 544.0)
# Its size at 1x: 256 px wide on a 1080p screen (brand: png/mark-lime-256.png),
# about 90 px high.
MARK_W = 256

# Moving parts, in art units (penguin.svg's coordinates).
PIVOT = (816.0, 618.0)     # the penguin turns (pitches) around this point
ROOT = (715.0, 688.0)      # the flipper's root, where it turns
PAD = 24.0                 # room around each part for turning
WATER = (73.4, 478.0, 726.0, 766.0)   # the wake's sheet: x0, y0, x1, y1
# Bubbles rise from these points around the end of the penguin's back.
SPAWN = [(592.0, 556.0), (560.0, 520.0), (536.0, 588.0)]
BUBBLES = (34.0, 16.0)     # diameters of the big and small bubble, art units

# The wake's flow: FRAMES frames at FPS, a seamless loop in which a swell of
# brightness PERIOD art units long moves one PERIOD to the left.
FPS = 25
FRAMES = 25
COLUMNS = 5
PERIOD = 170.0
LOW, HIGH = 0.62, 1.38     # the wake's opacity across the swell, x WAKE

# Progress: a water line PROGRESS_W x PROGRESS_H px at 1x, PERIODS waves,
# STROKE px thick.
PROGRESS_W, PROGRESS_H = 136, 8
PERIODS = 3
STROKE = 2.0

# Wordmark: WORDMARK_W px wide at 1x, its own aspect ratio.
WORDMARK_W = 136


def load_penguin(brand):
    text = (brand / "src/penguin.svg").read_text(encoding="utf-8")
    parts = {}
    for m in re.finditer(r'<path id="([^"]+)" data-box="([^"]+)" d="([^"]+)"/>', text):
        parts[m.group(1)] = (m.group(3), tuple(float(v) for v in m.group(2).split()))
    for key in ("body", "belly", "flipper", "eye", "water-1", "water-2"):
        if key not in parts:
            sys.exit(f"penguin.svg has no part {key!r}; update build.py")
    return parts


class Mark:
    def __init__(self, parts):
        self.parts = parts
        self.water_parts = [k for k in parts if k.startswith("water-")]
        boxes = [b for _, b in parts.values()]
        self.box = (min(b[0] for b in boxes), min(b[1] for b in boxes),
                    max(b[2] for b in boxes), max(b[3] for b in boxes))
        self.unit = MARK_W / (self.box[2] - self.box[0])   # 1x px per art unit
        fb = parts["flipper"][1]
        # The penguin's sprite: centred on PIVOT, large enough for every part
        # but the flipper (the body's tail fades out before RAMP[0]).
        hw = max(PIVOT[0] - RAMP[0], self.box[2] - PIVOT[0]) + PAD
        hh = max(PIVOT[1] - self.box[1], parts["belly"][1][3] - PIVOT[1]) + PAD
        self.penguin_view = (PIVOT[0] - hw, PIVOT[1] - hh, 2 * hw, 2 * hh)
        hw = max(ROOT[0] - fb[0], fb[2] - ROOT[0]) + PAD
        hh = max(ROOT[1] - fb[1], fb[3] - ROOT[1]) + PAD
        # Square, so the flipper's tip stays inside however it turns.
        r = max(hw, hh)
        self.flipper_view = (ROOT[0] - r, ROOT[1] - r, 2 * r, 2 * r)
        self.water_view = (WATER[0], WATER[1], WATER[2] - WATER[0], WATER[3] - WATER[1])

    def d(self, *keys):
        return "".join(f'<path d="{self.parts[k][0]}"/>' for k in keys)

    def px(self, length, scale):
        return max(1, round(length * self.unit * scale))

    def svg(self, body, view, scale):
        x, y, w, h = view
        return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.px(w, scale)}" '
                f'height="{self.px(h, scale)}" viewBox="{x:.2f} {y:.2f} {w:.2f} {h:.2f}">{body}</svg>')

    def _ramp(self, uid, inverse=False):
        """The brand's mask: the body from the gradient on, and the wing.
        Inverted: the part of the body that belongs to the wake."""
        x0, x1 = RAMP
        wx0, wy0, wx1, wy1 = WING
        a, b = ("1", "0") if inverse else ("0", "1")
        wing = "#000" if inverse else "#fff"
        return (f'<linearGradient id="{uid}g" gradientUnits="userSpaceOnUse" x1="{x0:g}" y1="0" x2="{x1:g}" y2="0">'
                f'<stop offset="0" stop-color="#fff" stop-opacity="{a}"/>'
                f'<stop offset="1" stop-color="#fff" stop-opacity="{b}"/></linearGradient>'
                f'<mask id="{uid}k" maskUnits="userSpaceOnUse" x="0" y="0" width="1300" height="1300">'
                f'<rect width="1300" height="1300" fill="url(#{uid}g)"/>'
                f'<rect x="{wx0:g}" y="{wy0:g}" width="{wx1 - wx0:g}" height="{wy1 - wy0:g}" fill="{wing}"/></mask>')

    def full(self):
        """The whole mark at rest: brand/src/build.py's mark_paths()."""
        wake = [k for k in self.parts if k.startswith(("water-", "bubble-"))]
        return (f'<defs>{self._ramp("m")}</defs><g fill="{LIME}">'
                f'<g fill-opacity="{WAKE:g}">{self.d(*wake, "body")}</g>'
                f'<g mask="url(#mk)">{self.d("body")}</g>'
                f'{self.d("belly", "flipper", "eye")}</g>')

    def penguin(self):
        """The penguin without its flipper and wake: the body from the
        gradient on (the wake's share of it is in the water sheet), the
        belly and the eye."""
        return (f'<defs>{self._ramp("p")}</defs><g fill="{LIME}">'
                f'<g mask="url(#pk)">{self.d("body")}</g>{self.d("belly", "eye")}</g>')

    def flipper(self):
        return f'<g fill="{LIME}">{self.d("flipper")}</g>'

    def water(self, frame):
        """The wake in one frame of its flow: the water lines and the body's
        tail, at WAKE opacity on average, brighter in a swell that moves one
        PERIOD to the left over FRAMES frames."""
        shift = -PERIOD * frame / FRAMES
        x0 = WATER[0] + shift
        stops = "".join(
            f'<stop offset="{i / 12:.4f}" stop-color="#fff" stop-opacity="'
            f'{WAKE * (LOW + (HIGH - LOW) * (0.5 - 0.5 * math.cos(2 * math.pi * i / 12))):.4f}"/>'
            for i in range(13))
        return (f'<defs>{self._ramp("w", inverse=True)}'
                f'<linearGradient id="sg" gradientUnits="userSpaceOnUse" spreadMethod="repeat" '
                f'x1="{x0:.3f}" y1="0" x2="{x0 + PERIOD:.3f}" y2="0">{stops}</linearGradient>'
                f'<mask id="sk" maskUnits="userSpaceOnUse" x="0" y="0" width="1300" height="1300">'
                f'<rect width="1300" height="1300" fill="url(#sg)"/></mask></defs>'
                f'<g fill="{LIME}" mask="url(#sk)">{self.d(*self.water_parts)}'
                f'<g mask="url(#wk)">{self.d("body")}</g></g>')

    def offsets(self):
        """agentux.script's constants: 1080p px from the mark's top-left."""
        u, (bx, by) = self.unit, self.box[:2]
        at = lambda x, y: (round((x - bx) * u, 2), round((y - by) * u, 2))
        c = {}
        c["MARK_H"] = round((self.box[3] - by) * u, 2)
        c["PIVOT_X"], c["PIVOT_Y"] = at(*PIVOT)
        c["ROOT_X"], c["ROOT_Y"] = at(*ROOT)
        c["WATER_X"], c["WATER_Y"] = at(WATER[0], WATER[1])
        for i, (x, y) in enumerate(SPAWN):
            c[f"SPAWN_X{i}"], c[f"SPAWN_Y{i}"] = at(x, y)
        return c


def ease(u):
    return u - 0.5 / (2 * math.pi) * math.sin(2 * math.pi * u)


def wave(w, h, color, scale):
    """A water line: PERIODS sine waves across w x h, round ends."""
    pad = STROKE * scale / 2 + 0.5
    amp = h / 2 - pad
    n = 240
    pts = []
    for i in range(n + 1):
        x = pad + (w - 2 * pad) * i / n
        y = h / 2 - amp * math.sin(2 * math.pi * PERIODS * i / n)
        pts.append(f"{x:.2f} {y:.2f}")
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'
            f'<path d="M{"L".join(pts)}" fill="none" stroke="{color}" stroke-width="{STROKE * scale:g}" '
            f'stroke-linecap="round" stroke-linejoin="round"/></svg>')


def circle(diameter_px):
    d = diameter_px + 2
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{d}" height="{d}">'
            f'<circle cx="{d / 2}" cy="{d / 2}" r="{diameter_px / 2}" fill="{LIME}"/></svg>')


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
    """Re-save as a palette PNG when that is lossless (few colours), to keep it small."""
    im = Image.open(path).convert("RGBA")
    if path.name.startswith(("water", "penguin", "flipper", "bubble")):
        # One colour, Lime, at varying opacity: resvg's edges carry a little
        # RGB noise from un-premultiplying; dropping it leaves at most 256
        # colours, so the palette PNG below applies.
        alpha = im.getchannel("A")
        im = Image.new("RGBA", im.size, LIME)
        im.putalpha(alpha)
    colours = im.getcolors(256)
    if colours is not None:
        q = im.quantize(colors=len(colours), method=Image.Quantize.FASTOCTREE)
        if q.convert("RGBA").tobytes() == im.tobytes():
            im = q
    buf = io.BytesIO()
    im.save(buf, "PNG", optimize=True)
    path.write_bytes(buf.getvalue())


def write_constants(constants):
    """Rewrites the `NAME = value;` lines of agentux.script's generated block."""
    script = SCRIPT.read_text(encoding="utf-8")
    for name, value in constants.items():
        pattern = re.compile(rf"^{name} = [^;]*;", re.M)
        if not pattern.search(script):
            sys.exit(f"agentux.script has no `{name} = ...;` line; add it to its generated block")
        script = pattern.sub(f"{name} = {value};", script, count=1)
    SCRIPT.write_text(script, encoding="utf-8", newline="\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--brand", type=Path, default=HERE.parent.parent / "agentux/brand",
                    help="the agentux repository's brand/ directory")
    args = ap.parse_args()
    wordmark = args.brand / "svg/wordmark-mist.svg"
    if not wordmark.is_file() or not (args.brand / "src/penguin.svg").is_file():
        sys.exit(f"{args.brand} has no svg/wordmark-mist.svg or src/penguin.svg; pass --brand")
    mark = Mark(load_penguin(args.brand))
    wm_svg = wordmark.read_text(encoding="utf-8")
    m = re.match(r'<svg [^>]*width="([0-9.]+)" height="([0-9.]+)"', wm_svg)
    wm_size = m.group(0)
    wm_ratio = float(m.group(2)) / float(m.group(1))
    tmp = HERE / ".build"
    tmp.mkdir(exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    for old in ("dashes", "wake", "mark"):  # earlier animations' images
        for suffix in ("", "@2x"):
            (OUT / f"{old}{suffix}.png").unlink(missing_ok=True)

    jobs = []
    for scale, suffix in ((1, ""), (2, "@2x")):
        jobs.append({"svg": mark.svg(mark.penguin(), mark.penguin_view, scale),
                     "out": str(OUT / f"penguin{suffix}.png")})
        jobs.append({"svg": mark.svg(mark.flipper(), mark.flipper_view, scale),
                     "out": str(OUT / f"flipper{suffix}.png")})
        for f in range(FRAMES):
            jobs.append({"svg": mark.svg(mark.water(f), mark.water_view, scale),
                         "out": str(tmp / f"water{suffix}-{f:02d}.png")})
        jobs.append({"svg": circle(mark.px(BUBBLES[0], scale)), "out": str(OUT / f"bubble{suffix}.png")})
        jobs.append({"svg": circle(mark.px(BUBBLES[1], scale)), "out": str(OUT / f"bubble-small{suffix}.png")})
        wm_w = WORDMARK_W * scale
        wm = wm_svg.replace(wm_size, wm_size.replace(m.group(1), str(wm_w), 1)
                            .replace(m.group(2), str(round(wm_w * wm_ratio)), 1), 1)
        jobs.append({"svg": wm, "out": str(OUT / f"wordmark{suffix}.png")})
        # Progress: a Lime water line over a Graphite one.
        pw, ph = PROGRESS_W * scale, PROGRESS_H * scale
        jobs.append({"svg": wave(pw, ph, GRAPHITE, scale), "out": str(OUT / f"track{suffix}.png")})
        jobs.append({"svg": wave(pw, ph, LIME, scale), "out": str(OUT / f"fill{suffix}.png")})
    # The whole mark at rest, for previews only (not installed).
    jobs.append({"svg": mark.svg(mark.full(), (mark.box[0], mark.box[1], mark.box[2] - mark.box[0],
                                               mark.box[3] - mark.box[1]), 1),
                 "out": str(tmp / "mark.png")})
    # Shapes that scale cleanly: drawn once at 2x.
    jobs += [
        # Passphrase field: Graphite, a quiet Slate edge.
        {"svg": rounded_rect(640, 88, 16, GRAPHITE, SLATE, 0.28), "out": str(OUT / "entry.png")},
        {"svg": ('<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20">'
                 f'<circle cx="10" cy="10" r="10" fill="{LIME}"/></svg>'), "out": str(OUT / "bullet.png")},
    ]
    render(jobs)

    # Frames go into one sheet per scale (agentux.script crops them), COLUMNS wide.
    for suffix in ("", "@2x"):
        frames = [Image.open(tmp / f"water{suffix}-{f:02d}.png") for f in range(FRAMES)]
        fw, fh = frames[0].size
        rows = math.ceil(FRAMES / COLUMNS)
        sheet = Image.new("RGBA", (fw * COLUMNS, fh * rows))
        for i, im in enumerate(frames):
            sheet.paste(im, ((i % COLUMNS) * fw, (i // COLUMNS) * fh))
        sheet.save(OUT / f"water{suffix}.png")
    constants = {"FRAMES": FRAMES, "COLUMNS": COLUMNS, "TICKS": round(50 / FPS)}
    constants.update(mark.offsets())
    write_constants(constants)
    for p in sorted(OUT.glob("*.png")):
        optimise(p)
        print(f"{p.relative_to(HERE.parent).as_posix()}  {Image.open(p).size}  {p.stat().st_size} bytes")
    total = sum(p.stat().st_size for p in OUT.glob("*.png"))
    print(f"total {total} bytes")
    for p in tmp.glob("*.png"):
        if p.name != "mark.png":
            p.unlink()


if __name__ == "__main__":
    main()
