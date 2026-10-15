#!/usr/bin/env python3
"""Builds the AgentUX art of the installer ISO's Anaconda into
installer/product/usr/share/anaconda/pixmaps/ (installer/brand-iso.sh packs
that tree into the ISO's images/product.img).

    cd plymouth && npm install && cd .. && python3 installer/build.py [--brand ../agentux/brand]

Uses plymouth/render.mjs (resvg, the renderer the brand assets use) and
Pillow. Anaconda's GTK interface draws its sidebar and title bar from these
files, named as Fedora's (fedora-logos ships them; Fedora's profile points
its stylesheet, fedora.css next to them, at them):

  sidebar-bg.png     the sidebar's background: Ink, a Graphite glow at the top
  sidebar-logo.png   on it, near the top: the full mark in Lime over the
                     wordmark in Mist
  topbar-bg.png      the title bar of every screen: Ink
  anaconda_header.png  the dark lockup, small

Edit this script, not the PNGs.
"""
import argparse
import io
import json
import re
import subprocess
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
OUT = HERE / "product/usr/share/anaconda/pixmaps"

INK = "#0b0d10"
GRAPHITE = "#171b20"


def placed(svg_text, x, y, w):
    """The brand SVG as a nested <svg> at (x, y), w wide; and its height."""
    m = re.match(r'<svg [^>]*width="([0-9.]+)" height="([0-9.]+)"', svg_text)
    if not m:
        sys.exit("a brand SVG has no width and height; update installer/build.py")
    h = w * float(m.group(2)) / float(m.group(1))
    head = m.group(0).replace(f'width="{m.group(1)}" height="{m.group(2)}"',
                              f'x="{x:.2f}" y="{y:.2f}" width="{w:.2f}" height="{h:.2f}"', 1)
    return svg_text.replace(m.group(0), head, 1), h


def doc(w, h, body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{body}</svg>'


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--brand", type=Path, default=REPO.parent / "agentux/brand",
                    help="the agentux repository's brand/ directory")
    args = ap.parse_args()
    read = lambda name: (args.brand / "svg" / name).read_text(encoding="utf-8")
    try:
        mark, wordmark, lockup = read("mark-lime.svg"), read("wordmark-mist.svg"), read("lockup-dark.svg")
    except FileNotFoundError as e:
        sys.exit(f"{e.filename} not found; pass --brand")

    jobs = []

    # The sidebar: Ink, with a faint Graphite glow where the logo sits.
    w, h = 406, 767
    glow = (f'<defs><radialGradient id="g" cx="0.5" cy="0.08" r="0.6">'
            f'<stop offset="0" stop-color="{GRAPHITE}"/><stop offset="1" stop-color="{INK}"/>'
            f'</radialGradient></defs><rect width="{w}" height="{h}" fill="url(#g)"/>')
    jobs.append(("sidebar-bg.png", doc(w, h, glow)))

    # The logo: the full mark over the wordmark, 150 px wide, transparent.
    lw = 150
    m, mh = placed(mark, 0, 0, lw)
    ww = lw * 0.8
    wm, wh = placed(wordmark, (lw - ww) / 2, mh + 12, ww)
    jobs.append(("sidebar-logo.png", doc(lw, round(mh + 12 + wh), m + wm)))

    # The title bar: Ink.
    jobs.append(("topbar-bg.png", doc(1040, 132, f'<rect width="1040" height="132" fill="{INK}"/>')))

    # The small header: the dark lockup, transparent, 119 x 36.
    lk, lh = placed(lockup, 0, 0, 119)
    lk, lh = placed(lockup, 0, (36 - lh) / 2, 119)
    jobs.append(("anaconda_header.png", doc(119, 36, lk)))

    OUT.mkdir(parents=True, exist_ok=True)
    plymouth = REPO / "plymouth"
    subprocess.run(["node", str(plymouth / "render.mjs")],
                   input=json.dumps([{"svg": svg, "out": str(OUT / name)} for name, svg in jobs]).encode(),
                   check=True, cwd=plymouth)
    for name, _ in jobs:
        f = OUT / name
        im = Image.open(f)
        buf = io.BytesIO()
        im.save(buf, "PNG", optimize=True)
        f.write_bytes(buf.getvalue())
        print(f"{f.relative_to(REPO).as_posix()}  {im.size[0]}x{im.size[1]}  {f.stat().st_size} bytes")


if __name__ == "__main__":
    main()
