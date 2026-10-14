#!/usr/bin/env python3
"""Renders the boot splash's animation without booting: composes the theme's
images the way agentux.script moves them on a 1080p screen (the swimming
penguin and its flipper, the water sheet, the bubbles, the wordmark and the
progress line) and writes an animated GIF of one swim cycle, cropped to the
middle of the screen. It reads the constants from agentux.script and
follows swim() step by step.

    python3 preview.py [OUT.gif]     # default: docs/plymouth/animation.gif

For the real thing, plymouth/preview-vm.sh boots the image's initramfs in QEMU
and captures what Plymouth draws, passphrase prompt included.
"""
import math
import re
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
THEME = HERE.parent / "files/usr/share/plymouth/themes/agentux"
INK = (11, 13, 16)
W, H = 1920, 1080          # scale 1: the 1x images as they are
CROP = (780, 390, 1140, 630)
ZOOM = 1.25                # the GIF shows the crop 1.25x, so the motion reads


def constants(script):
    return {m.group(1): float(m.group(2))
            for m in re.finditer(r"^([A-Z_0-9]+) = (-?[0-9.]+);", script, re.M)}


def with_opacity(im, a):
    im = im.copy()
    im.putalpha(im.getchannel("A").point(lambda v: round(v * a)))
    return im


def rotate(im, radians):
    # Plymouth's Image.Rotate keeps the size and turns about the centre.
    return im.rotate(-math.degrees(radians), resample=Image.BICUBIC)


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE.parent / "docs/plymouth/animation.gif"
    c = constants((THEME / "agentux.script").read_text(encoding="utf-8"))
    frames_n, columns, ticks = int(c["FRAMES"]), int(c["COLUMNS"]), int(c["TICKS"])

    def img(name):
        return Image.open(THEME / f"{name}.png").convert("RGBA")

    penguin, flipper, wordmark = img("penguin"), img("flipper"), img("wordmark")
    big, small = img("bubble"), img("bubble-small")
    track, fill = img("track"), img("fill")
    sheet = img("water")
    fw, fh = sheet.width // columns, sheet.height // -(-frames_n // columns)
    water = [sheet.crop(((i % columns) * fw, (i // columns) * fh,
                         (i % columns + 1) * fw, (i // columns + 1) * fh)) for i in range(frames_n)]

    # layout() in agentux.script, at scale 1.
    mark_w, mark_h, gap = 256, c["MARK_H"], 28
    group = mark_h + gap + wordmark.height
    top = H * 0.47 - group / 2
    mark_x, mark_y = W / 2 - mark_w / 2, top
    wm_xy = (int(W / 2 - wordmark.width / 2), int(top + mark_h + gap))
    below = int(top + mark_h + gap + wordmark.height + 40)
    tx = int(W / 2 - track.width / 2)

    def paste(screen, im, x, y, opacity=1.0):
        if opacity < 1:
            im = with_opacity(im, opacity)
        screen.alpha_composite(im, (int(x), int(y)))

    images = []
    cycle = int(c["CYCLE"])
    for t in range(0, cycle, ticks):     # one swim cycle, every frame Plymouth draws
        screen = Image.new("RGBA", (W, H), INK + (255,))
        a = 2 * math.pi * (t % cycle) / cycle
        bob = c["BOB"] * math.sin(a)
        pitch = -c["PITCH"] * math.cos(a)
        flap = c["FLAP"] * math.sin(2 * a)
        mx, my = mark_x, mark_y + bob
        # z order: water 10, bubbles 11, penguin 12, flipper 13.
        paste(screen, water[(t // ticks) % frames_n], mx + c["WATER_X"], my + c["WATER_Y"])
        for i in range(int(c["BUBBLE_COUNT"])):
            # Steady state: every bubble has been born already.
            age = t + cycle - i * c["BUBBLE_EVERY"]
            n = int(age // c["BUBBLE_LIFE"])
            age -= n * c["BUBBLE_LIFE"]
            v = (n + i) % 3
            sx, sy = c[f"SPAWN_X{v}"], c[f"SPAWN_Y{v}"]
            b = big if (n + i) % 2 == 0 else small
            life = age / c["BUBBLE_LIFE"]
            x = mx + sx - c["BUBBLE_VX"] * age / 50
            y = mark_y + sy - c["BUBBLE_VY"] * age / 50 + c["BUBBLE_WOBBLE"] * math.sin(3 * math.pi * life)
            paste(screen, b, x - b.width / 2, y - b.height / 2, c["BUBBLE_ALPHA"] * math.sin(math.pi * life))
        p = rotate(penguin, pitch)
        paste(screen, p, mx + c["PIVOT_X"] - p.width / 2, my + c["PIVOT_Y"] - p.height / 2)
        f = rotate(flipper, pitch + flap)
        paste(screen, f, mx + c["ROOT_X"] - f.width / 2, my + c["ROOT_Y"] - f.height / 2)
        paste(screen, wordmark, *wm_xy)
        paste(screen, track, tx, below)
        w = round(track.width * (0.2 + 0.45 * t / cycle))
        paste(screen, fill.crop((0, 0, w, fill.height)), tx, below)
        frame = screen.crop(CROP).convert("RGB")
        frame = frame.resize((round(frame.width * ZOOM), round(frame.height * ZOOM)), Image.LANCZOS)
        images.append(frame)
    out.parent.mkdir(parents=True, exist_ok=True)
    images[0].save(out, save_all=True, append_images=images[1:], loop=0,
                   duration=round(1000 * ticks / 50), optimize=True)
    print(f"{out}  {out.stat().st_size} bytes, {len(images)} frames")


if __name__ == "__main__":
    main()
