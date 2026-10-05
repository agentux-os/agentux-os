#!/usr/bin/env python3
"""Renders the boot splash's animation without booting: composes the theme's
images the way agentux.script lays them out on a 1080p screen (mark, dash
frames, wordmark, progress) and writes an animated GIF of one loop, cropped
to the middle of the screen.

    python3 preview.py [OUT.gif]     # default: docs/plymouth/animation.gif

For the real thing, plymouth/preview-vm.sh boots the image's initramfs in QEMU
and captures what Plymouth draws, passphrase prompt included.
"""
import re
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
THEME = HERE.parent / "files/usr/share/plymouth/themes/agentux"
INK = (11, 13, 16)
W, H = 1920, 1080          # scale 1: the 1x images as they are
CROP = (720, 300, 1200, 640)


def constant(script, name):
    return float(re.search(rf"^{name} = ([0-9.]+);", script, re.M).group(1))


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE.parent / "docs/plymouth/animation.gif"
    script = (THEME / "agentux.script").read_text()
    frames_n, columns, ticks, pause, dim = (constant(script, n) for n in
                                            ("FRAMES", "COLUMNS", "TICKS", "PAUSE", "DIM"))
    frames_n, columns, pause = int(frames_n), int(columns), int(pause)

    mark = Image.open(THEME / "mark.png").convert("RGBA")
    wordmark = Image.open(THEME / "wordmark.png").convert("RGBA")
    sheet = Image.open(THEME / "dashes.png").convert("RGBA")
    fw, fh = sheet.width // columns, sheet.height // -(-frames_n // columns)
    dashes = [sheet.crop(((i % columns) * fw, (i // columns) * fh,
                          (i % columns + 1) * fw, (i // columns + 1) * fh)) for i in range(frames_n)]
    track = Image.open(THEME / "track.png").convert("RGBA")
    fill = Image.open(THEME / "fill.png").convert("RGBA")

    # layout() in agentux.script, at scale 1.
    gap = 30
    group = mark.height + gap + wordmark.height
    top = int(H * 0.47 - group / 2)
    mark_xy = (W // 2 - mark.width // 2, top)
    wm_xy = (W // 2 - wordmark.width // 2, top + mark.height + gap)
    below = int(wm_xy[1] + wordmark.height + 44)
    track_w = 112
    track_img = track.resize((track_w, 2))

    def opacity(im, a):
        im = im.copy()
        im.putalpha(im.getchannel("A").point(lambda v: round(v * a)))
        return im

    dim_mark = opacity(mark, dim)
    images = []
    total = frames_n + pause
    for f in range(total):
        screen = Image.new("RGBA", (W, H), INK + (255,))
        screen.alpha_composite(dim_mark, mark_xy)
        if f < frames_n:
            screen.alpha_composite(dashes[f], mark_xy)
        screen.alpha_composite(wordmark, wm_xy)
        x = W // 2 - track_w // 2
        screen.alpha_composite(track_img, (x, below))
        w = round(track_w * (0.15 + 0.5 * f / total))
        screen.alpha_composite(fill.resize((w, 2)), (x, below))
        images.append(screen.crop(CROP).convert("RGB"))
    out.parent.mkdir(parents=True, exist_ok=True)
    # Plymouth refreshes at 50 Hz and shows each frame for TICKS refreshes.
    images[0].save(out, save_all=True, append_images=images[1:], loop=0,
                   duration=round(1000 * ticks / 50), optimize=True)
    print(f"{out}  {out.stat().st_size} bytes, {len(images)} frames")


if __name__ == "__main__":
    main()
