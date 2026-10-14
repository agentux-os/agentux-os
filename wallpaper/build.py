#!/usr/bin/env python3
"""Builds wallpaper/wizard-{dark,light}.svg, the art of the AgentUX-Default
wallpaper package (the first-boot wizard's background), from the brand's key
art next to it (wallpaper-{dark,light}.svg, copies of brand/art/ in the
agentux repository).

    python3 wallpaper/build.py

The key art puts the swimming penguin large, right of centre, where
plasma-setup draws its centred "Welcome to Plasma Desktop" and "Begin Setup"
over it. The wizard's version keeps the water currents and moves the mark,
smaller, to the lower third of the screen, centred: clear of the wizard's
text and buttons, and inside the portrait crop the Containerfile takes from
the middle of the picture. Standard library only; edit this, not the output.
"""
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent

W, H = 3840, 2160
# The mark's bounds in the brand's art coordinates (brand/src/build.py's
# FULL_BOX: penguin.svg's parts, wake included).
BOX = (73.4, 425.4, 1168.0, 810.0)
WIDTH = 0.20 * W      # the mark's width: a fifth of the screen
CENTRE = (0.50 * W, 0.72 * H)


def main():
    s = WIDTH / (BOX[2] - BOX[0])
    cx, cy = (BOX[0] + BOX[2]) / 2, (BOX[1] + BOX[3]) / 2
    tx, ty = CENTRE[0] - cx * s, CENTRE[1] - cy * s
    for theme in ("dark", "light"):
        art = (HERE / f"wallpaper-{theme}.svg").read_text(encoding="utf-8")
        groups = re.findall(r'<g transform="translate\([-0-9. ]+\) scale\([0-9.]+\)"', art)
        if len(groups) != 1:
            raise SystemExit(f"wallpaper-{theme}.svg: expected one placed mark, found {len(groups)}; update wallpaper/build.py")
        out = art.replace(groups[0], f'<g transform="translate({tx:.3f} {ty:.3f}) scale({s:.5f})"', 1)
        (HERE / f"wizard-{theme}.svg").write_text(out, encoding="utf-8", newline="\n")
        print(f"wallpaper/wizard-{theme}.svg: mark {WIDTH:.0f} px wide at {CENTRE[0]:.0f},{CENTRE[1]:.0f}")


if __name__ == "__main__":
    main()
