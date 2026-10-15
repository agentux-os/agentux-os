#!/usr/bin/bash
# Brands bootc-image-builder's installer ISO (anaconda-iso) as AgentUX.
#
#   brand-iso.sh IN.iso OUT.iso VERSION
#
# VERSION is what the installer calls this AgentUX: the release tag (v0.5.3)
# for a release ISO, "nightly" otherwise.
#
# bootc-image-builder builds the installer environment from Fedora's
# packages, so its Anaconda shows Fedora's logo and colours, its boot menu
# says "Install AgentUX 44" (os-release NAME and Fedora's VERSION_ID) and the
# ISO's volume label is Fedora's; its config has no setting for any of it.
# This changes only how the ISO looks, not what it installs (the embedded,
# signed image and bootc-image-builder's kickstart with its `bootc switch` to
# the channel stay byte for byte):
#
#   images/product.img  Anaconda's own mechanism for product branding: its
#                       initramfs unpacks images/product.img from the
#                       installation source over the installer environment
#                       before Anaconda starts. Ours (installer/product/,
#                       gzipped cpio) has the AgentUX stylesheet and art in
#                       place of Fedora's (fedora.css and the pixmaps
#                       Fedora's profile loads) and a .buildstamp naming the
#                       product AgentUX <VERSION>.
#   volume label        AgentUX-<version>-<arch> instead of
#                       Fedora-S-dvd-<arch>-44, in the volume descriptor and
#                       in every boot entry that finds stage 2 by it.
#   boot menu           "Install AgentUX <version>" in the ISO's grub.cfg
#                       files, on the ISO and inside its EFI boot image.
#
# xorriso rewrites the ISO keeping its boot setup (El Torito BIOS and EFI,
# the hybrid MBR/GPT; -boot_image any replay), and the media check checksum
# is implanted again (implantisomd5), since "Test this media" checks it.
#
# Needs xorriso, mtools, cpio, gzip and implantisomd5 (isomd5sum).
set -euo pipefail

in="$(realpath "${1:?usage: brand-iso.sh IN.iso OUT.iso VERSION}")"
out="${2:?usage: brand-iso.sh IN.iso OUT.iso VERSION}"
version="${3:?usage: brand-iso.sh IN.iso OUT.iso VERSION}"
here="$(cd "$(dirname "$0")" && pwd)"
[[ $version =~ ^[A-Za-z0-9._-]+$ ]] || { echo "VERSION '$version' must be [A-Za-z0-9._-]" >&2; exit 2; }
for tool in xorriso mtype mcopy mdir cpio gzip implantisomd5; do
    command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
done

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

x() { xorriso -indev "$in" "$@" 2>/dev/null; }
extract() { xorriso -osirrox on -indev "$in" -extract "$1" "$2" 2>/dev/null; }
old_label="$(x -pvd_info | sed -n 's/^Volume Id *: *//p' | head -n1)"
[[ -n $old_label ]] || { echo "cannot read the ISO's volume label" >&2; exit 1; }
arch="$(sed -nE 's/.*(x86_64|aarch64).*/\1/p' <<<"$old_label")"
[[ -n $arch ]] || arch="$(uname -m)"
label="AgentUX-$version-$arch"
(( ${#label} <= 32 )) || { echo "label $label is longer than 32 characters" >&2; exit 1; }
echo "volume label: $old_label -> $label"

# The menu's product name: "AgentUX <version>" ("AgentUX nightly").
title="AgentUX $version"

# rewrite_cfg FILE: the new label everywhere, and the menu entries' titles.
# bootc-image-builder names them "<NAME> <VERSION_ID>" ("Install AgentUX
# 44"); should it ever say Fedora, that goes too. "--class fedora" (an icon
# class for GRUB themes) stays.
rewrite_cfg() {
    sed -i -E \
        -e "s/$(sed 's/[.[\*^$/]/\\&/g' <<<"$old_label")/$label/g" \
        -e "/^[[:space:]]*(menuentry|submenu)[[:space:]]/{
              s/AgentUX [0-9]+([.][0-9]+)*/$title/g
              s/Fedora( Linux)?( [0-9]+)?/$title/g
              s/ a AgentUX / an AgentUX /g
           }" \
        "$1"
}

# ---- the ISO's grub.cfg files ------------------------------------------------------

maps=()
mapfile -t cfgs < <(x -find / -type f -name grub.cfg | sed -E "s/^'(.*)'$/\1/" | grep '^/' || true)
(( ${#cfgs[@]} > 0 )) || { echo "no grub.cfg on the ISO" >&2; exit 1; }
i=0
for cfg in "${cfgs[@]}"; do
    f="$work/cfg-$i"
    extract "$cfg" "$f"
    chmod u+w "$f"
    rewrite_cfg "$f"
    echo "== $cfg"
    grep -E '^[[:space:]]*(menuentry|submenu|search)' "$f" | sed 's/^/    /' || true
    maps+=(-map "$f" "$cfg")
    i=$((i + 1))
done

# ---- the EFI boot image's grub.cfg -------------------------------------------------

mapfile -t efiimgs < <(x -find / -type f -name efiboot.img | sed -E "s/^'(.*)'$/\1/" | grep '^/' || true)
for img in "${efiimgs[@]}"; do
    f="$work/efiboot-$i.img"
    extract "$img" "$f"
    chmod u+w "$f"
    mapfile -t inner < <(mdir -/ -b -i "$f" :: 2>/dev/null | grep -i '/grub\.cfg$' || true)
    for cfg in "${inner[@]}"; do
        c="$work/inner-$i.cfg"
        mtype -i "$f" "$cfg" >"$c"
        rewrite_cfg "$c"
        mcopy -o -i "$f" "$c" "$cfg"
        echo "== $img:${cfg#::}"
        grep -E '^[[:space:]]*(menuentry|submenu|search)' "$c" | sed 's/^/    /' || true
        i=$((i + 1))
    done
    maps+=(-map "$f" "$img")
done

# ---- product.img -------------------------------------------------------------------------

tree="$work/product"
mkdir -p "$tree"
cp -a "$here/product/." "$tree/"
# Anaconda reads the product from .buildstamp. A nightly is pre-release
# software (Anaconda says so); a release is not.
isfinal=False
[[ $version == v[0-9]* ]] && isfinal=True
cat >"$tree/.buildstamp" <<EOF
[Main]
Product=AgentUX
Version=${version#v}
BugURL=https://github.com/agentux-os/agentux-os/issues
IsFinal=$isfinal
UUID=$(date -u +%Y%m%d%H%M).$arch
Variant=
[Compose]
AgentUX=$version
EOF
(cd "$tree" && find . -mindepth 1 | LC_ALL=C sort | cpio --quiet -o -H newc --owner=0:0) | gzip -9 >"$work/product.img"
echo "== /images/product.img"
zcat "$work/product.img" | cpio --quiet -t | sed 's/^/    /'
maps+=(-map "$work/product.img" /images/product.img)

# ---- the new ISO ---------------------------------------------------------------------------

rm -f "$out"
xorriso -indev "$in" -outdev "$out" \
    -volid "$label" \
    -boot_image any replay \
    "${maps[@]}" \
    -end
implantisomd5 --force "$out" >/dev/null

# ---- checks --------------------------------------------------------------------------------

y() { xorriso -indev "$out" "$@" 2>/dev/null; }
got="$(y -pvd_info | sed -n 's/^Volume Id *: *//p' | head -n1)"
[[ $got == "$label" ]] || { echo "the new ISO's label is '$got', not $label" >&2; exit 1; }
for cfg in "${cfgs[@]}"; do
    f="$work/check.cfg"
    rm -f "$f"
    xorriso -osirrox on -indev "$out" -extract "$cfg" "$f" 2>/dev/null
    if grep -q "$old_label" "$f"; then echo "$cfg still names $old_label" >&2; exit 1; fi
    if grep -E '^[[:space:]]*(menuentry|submenu)' "$f" | grep -qE 'Fedora|AgentUX [0-9]+'; then
        echo "$cfg still has Fedora's names in its menu" >&2; exit 1
    fi
done
rm -f "$work/check.img"
xorriso -osirrox on -indev "$out" -extract /images/product.img "$work/check.img" 2>/dev/null
cmp -s "$work/check.img" "$work/product.img" || { echo "/images/product.img is missing from the new ISO" >&2; exit 1; }
echo "== boot records of the new ISO"
y -report_el_torito plain | sed 's/^/    /'
echo "branded: $out ($label)"
