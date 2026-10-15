#!/usr/bin/env python3
"""Tells from a screendump (binary PPM, QEMU's default format) whether
Anaconda is on screen and whose colours it wears; used by tests/iso-vm.sh.

  installer-look.py FRAME.ppm

Prints the measurements and exits 0 when the installer is up in AgentUX's
colours (Ink panels, the Lime mark), 1 when it shows Fedora's or Anaconda's
default blue, 2 when no installer is on screen yet (a black or text screen).

Anaconda's GTK interface fills its sidebar and every title bar with the
product colour: Fedora's blue (#51a2da, with #3c6eb4 and #294172 in its
art) or, without a product stylesheet, Anaconda's own #2f4265. AgentUX's are
Ink (#0b0d10) panels with the mark in Lime (#c6f36b). The window's content
area is light, which is how a drawn installer is told from a boot screen.
"""
import sys

FEDORA = [(0x51, 0xa2, 0xda), (0x3c, 0x6e, 0xb4), (0x29, 0x41, 0x72), (0x2f, 0x42, 0x65)]
LIME = (0xc6, 0xf3, 0x6b)


def read_ppm(path):
    data = open(path, "rb").read()
    fields, pos = [], 0
    while len(fields) < 4:
        while data[pos:pos + 1].isspace():
            pos += 1
        if data[pos:pos + 1] == b"#":
            pos = data.index(b"\n", pos) + 1
            continue
        end = pos
        while not data[end:end + 1].isspace():
            end += 1
        fields.append(data[pos:end])
        pos = end
    if fields[0] != b"P6" or int(fields[3]) != 255:
        sys.exit(f"{path}: not an 8-bit binary PPM")
    w, h = int(fields[1]), int(fields[2])
    return w, h, data[pos + 1:pos + 1 + w * h * 3]


def near(p, c, tol):
    return abs(p[0] - c[0]) <= tol and abs(p[1] - c[1]) <= tol and abs(p[2] - c[2]) <= tol


def main(argv):
    if len(argv) != 2:
        sys.exit(__doc__)
    w, h, px = read_ppm(argv[1])
    n = fedora = lime = ink = bright = 0
    # Every other pixel of every other row is plenty.
    for y in range(0, h, 2):
        row = y * w * 3
        for x in range(0, w, 2):
            i = row + x * 3
            p = (px[i], px[i + 1], px[i + 2])
            n += 1
            if sum(p) > 3 * 180:
                bright += 1
            if any(near(p, c, 24) for c in FEDORA):
                fedora += 1
            elif near(p, LIME, 40):
                lime += 1
            elif max(p) <= 0x22:
                ink += 1
    share = lambda k: k / n
    print(f"{w}x{h}: light {share(bright):.1%}, dark/Ink {share(ink):.1%}, "
          f"Lime {share(lime):.2%}, Fedora/Anaconda blue {share(fedora):.2%}")
    if share(bright) < 0.2:
        print("no installer on screen yet")
        return 2
    if share(fedora) > 0.01:
        print("the installer wears Fedora's (or Anaconda's default) blue")
        return 1
    if share(ink) < 0.03 or lime == 0:
        print("the installer is up, but without AgentUX's Ink panels and Lime mark")
        return 1
    print("the installer wears AgentUX's colours")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
