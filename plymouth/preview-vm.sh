#!/usr/bin/bash
# Shows what Plymouth really draws, without installing anything: builds the
# Containerfile's boot splash step on top of the base image (the same RUN
# block, so the same initramfs), then boots that kernel and initramfs in QEMU
# (software emulation, in a container; no KVM needed) and saves a screenshot
# every half second. There is no root disk, so the boot stays on the splash.
#
#   plymouth/preview-vm.sh [OUT_DIR]       default: output/plymouth-preview
#
# Two boots, each RESOLUTION (default 1920x1080, e.g. RESOLUTION=3840x2160):
#   boot/    the splash with its animation and progress
#   unlock/  a LUKS disk on the command line: the passphrase prompt, with a
#            few keys typed into it
# Needs podman (or docker, with ENGINE=docker); runs the QEMU container
# privileged, for cryptsetup. Takes a few minutes per boot.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(dirname "$here")"
out="$(mkdir -p "${1:-$repo/output/plymouth-preview}" && cd "${1:-$repo/output/plymouth-preview}" && pwd)"
engine="${ENGINE:-podman}"
res="${RESOLUTION:-1920x1080}"
seconds="${PREVIEW_SECONDS:-90}"
tag=localhost/agentux-splash-preview

base="$(sed -n 's/^FROM //p' "$repo/Containerfile" | head -n1)"
base="${base//\$\{FEDORA_VERSION\}/$(sed -n 's/^ARG FEDORA_VERSION=//p' "$repo/Containerfile")}"
{
    echo "FROM $base"
    echo "COPY files/usr/share/plymouth/ /usr/share/plymouth/"
    sed -n '/^# Boot splash/,/^$/p' "$repo/Containerfile" | grep -v '^#'
} >"$out/Containerfile"
"$engine" build -t "$tag" -f "$out/Containerfile" "$repo"
"$engine" run --rm -v "$out:/out:z" "$tag" sh -c \
    'cp /usr/lib/modules/*/vmlinuz /usr/lib/modules/*/initramfs.img /out/'

# The script below runs in the container; its variables expand there.
# shellcheck disable=SC2016
"$engine" run --rm --privileged -v "$out:/out:z" -e RES="$res" -e SECONDS_="$seconds" \
    quay.io/fedora/fedora:latest bash -euo pipefail -c '
dnf -y -q install qemu-system-x86-core qemu-device-display-virtio-vga cryptsetup python3 >/tmp/dnf.log 2>&1 \
    || { cat /tmp/dnf.log; exit 1; }
cd /out
boot() {
    local name="$1" extra="$2" keys_at="$3"; shift 3
    rm -rf "$name" && mkdir "$name"
    qemu-system-x86_64 -accel tcg,thread=multi -m 2048 -smp 4 \
        -kernel vmlinuz -initrd initramfs.img \
        -append "rhgb quiet root=UUID=00000000-0000-0000-0000-000000000000 rd.timeout=600 $extra" \
        -device "virtio-vga,xres=${RES%x*},yres=${RES#*x}" -display none -serial none "$@" \
        -qmp unix:/tmp/qmp.sock,server=on,wait=off -daemonize -pidfile /tmp/qemu.pid
    python3 - "$name" "$SECONDS_" "$keys_at" <<"EOF"
import json, socket, sys, time
name, secs, keys_at = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
time.sleep(1)
s = socket.socket(socket.AF_UNIX)
s.connect("/tmp/qmp.sock")
f = s.makefile("rw")
def cmd(c):
    f.write(json.dumps(c) + "\n"); f.flush()
    while "event" in (r := json.loads(f.readline())):
        pass
    return r
f.readline()
cmd({"execute": "qmp_capabilities"})
t0, i, typed = time.time(), 0, 0
while (t := time.time() - t0) < secs:
    cmd({"execute": "screendump", "arguments": {"filename": f"/out/{name}/{i:03d}-{t:05.1f}s.png", "format": "png"}})
    if keys_at and t > keys_at and typed < 8:
        cmd({"execute": "human-monitor-command", "arguments": {"command-line": "sendkey a"}})
        typed += 1
    i += 1
    time.sleep(0.5)
cmd({"execute": "quit"})
EOF
    echo "$name: $(ls "$name" | wc -l) screenshots"
}
boot boot "" 0
rm -f luks.img && truncate -s 64M luks.img
echo -n preview | cryptsetup luksFormat --batch-mode --type luks2 --pbkdf pbkdf2 --pbkdf-force-iterations 1000 luks.img -
boot unlock "rd.luks.uuid=$(cryptsetup luksUUID luks.img)" "$((SECONDS_ * 3 / 4))" \
    -drive file=luks.img,if=virtio,format=raw
rm -f luks.img vmlinuz initramfs.img
'
echo "screenshots in $out/boot and $out/unlock"
