#!/usr/bin/env python3
"""Boot splash frames for tests/boot-vm.sh: turns the QEMU screendumps (PPM)
in a directory into PNGs, and reports whether any of them shows the AgentUX
boot splash (an Ink screen with Lime on it, the mark).

    splash.py DIR     prints one line for the job summary; exits 0 either way

Standard library only: the runner's python3 has no Pillow.
"""
import os
import struct
import sys
import zlib
from pathlib import Path

INK = (11, 13, 16)


def read_ppm(path):
    data = path.read_bytes()
    fields, pos = [], 0
    while len(fields) < 4:
        while data[pos:pos + 1].isspace():
            pos += 1
        if data[pos:pos + 1] == b"#":
            pos = data.index(b"\n", pos)
            continue
        end = pos
        while not data[end:end + 1].isspace():
            end += 1
        fields.append(data[pos:end])
        pos = end
    if fields[0] != b"P6" or fields[3] != b"255":
        raise ValueError(f"{path}: not an 8-bit P6 PPM")
    w, h = int(fields[1]), int(fields[2])
    return w, h, data[pos + 1:pos + 1 + w * h * 3]


def write_png(path, w, h, rgb):
    def chunk(kind, body):
        return (struct.pack(">I", len(body)) + kind + body
                + struct.pack(">I", zlib.crc32(kind + body) & 0xffffffff))
    stride = w * 3
    raw = b"".join(b"\0" + rgb[y * stride:(y + 1) * stride] for y in range(h))
    path.write_bytes(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(raw, 6))
                     + chunk(b"IEND", b""))


def is_splash(w, h, rgb):
    """Mostly Ink, with some Lime (the mark, lit or dimmed) on it."""
    ink = lime = total = 0
    step = 4
    for y in range(0, h, step):
        row = rgb[y * w * 3:(y + 1) * w * 3]
        for x in range(0, w * 3, 3 * step):
            r, g, b = row[x], row[x + 1], row[x + 2]
            total += 1
            if abs(r - INK[0]) <= 6 and abs(g - INK[1]) <= 6 and abs(b - INK[2]) <= 6:
                ink += 1
            elif g > 120 and g > r + 15 and r > b + 25:
                lime += 1
    return total and ink / total > 0.9 and lime >= 20


def main():
    d = Path(sys.argv[1])
    frames = sorted(d.glob("*.ppm"))
    if not frames:
        print("no frames captured")
        return
    t0 = frames[0].stat().st_mtime
    seen = []
    for ppm in frames:
        t = ppm.stat().st_mtime - t0
        try:
            w, h, rgb = read_ppm(ppm)
        except (ValueError, IndexError) as e:
            print(f"skipping {ppm.name}: {e}", file=sys.stderr)
            continue
        if is_splash(w, h, rgb):
            seen.append((t, ppm.stem))
        write_png(ppm.with_suffix(".png"), w, h, rgb)
        os.remove(ppm)
    if seen:
        print(f"seen in {len(seen)} of {len(frames)} frames, "
              f"{seen[0][0]:.0f}s to {seen[-1][0]:.0f}s after the first (first: {seen[0][1]}.png)")
    else:
        print(f"not seen in {len(frames)} frames")


if __name__ == "__main__":
    main()
