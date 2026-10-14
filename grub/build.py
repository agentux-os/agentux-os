#!/usr/bin/env python3
"""Builds the AgentUX GRUB theme's background into
files/usr/share/agentux/grub/background.png (theme.txt next to it
lays the menu out on it).

    cd plymouth && npm install && cd .. && python3 grub/build.py [--brand ../agentux/brand]

Uses plymouth/render.mjs (resvg, the renderer the brand assets use) and
Pillow. The art: the flat Ink screen of the boot splash (a gradient bands in
GRUB's 8-bit colour) and the brand's full mark (svg/mark-lime.svg) in the lower part
of the screen, under the menu. 1920 x 1080; theme.txt crops it to other
screen sizes. Edit this script, not the PNG.
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
OUT = REPO / "files/usr/share/agentux/grub/background.png"

W, H = 1920, 1080
INK = "#0b0d10"
MARK_W = 300          # the mark's width, px
MARK_CY = 0.735       # the mark's centre, as a fraction of the height


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--brand", type=Path, default=REPO.parent / "agentux/brand",
                    help="the agentux repository's brand/ directory")
    args = ap.parse_args()
    mark_file = args.brand / "svg/mark-lime.svg"
    if not mark_file.is_file():
        sys.exit(f"{mark_file} not found; pass --brand")
    mark = mark_file.read_text(encoding="utf-8")
    m = re.match(r'<svg [^>]*width="([0-9.]+)" height="([0-9.]+)"', mark)
    if not m:
        sys.exit("mark-lime.svg has no width and height; update grub/build.py")
    mw, mh = MARK_W, MARK_W * float(m.group(2)) / float(m.group(1))
    x, y = (W - mw) / 2, H * MARK_CY - mh / 2
    mark = mark.replace(m.group(0), m.group(0).replace(
        f'width="{m.group(1)}" height="{m.group(2)}"',
        f'x="{x:.2f}" y="{y:.2f}" width="{mw:.2f}" height="{mh:.2f}"', 1), 1)
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">'
           f'<rect width="{W}" height="{H}" fill="{INK}"/>{mark}</svg>')
    OUT.parent.mkdir(parents=True, exist_ok=True)
    plymouth = REPO / "plymouth"
    subprocess.run(["node", str(plymouth / "render.mjs")],
                   input=json.dumps([{"svg": svg, "out": str(OUT)}]).encode(),
                   check=True, cwd=plymouth)
    # GRUB's PNG reader wants 8-bit, non-interlaced; no alpha needed.
    im = Image.open(OUT).convert("RGB")
    buf = io.BytesIO()
    im.save(buf, "PNG", optimize=True)
    OUT.write_bytes(buf.getvalue())
    print(f"{OUT.relative_to(REPO).as_posix()}  {im.size[0]}x{im.size[1]}  {OUT.stat().st_size} bytes")


if __name__ == "__main__":
    main()
