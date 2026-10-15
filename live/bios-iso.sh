#!/usr/bin/bash
# Adds legacy BIOS boot to the x86_64 live ISO that Titanoboa wrote.
#
#   bios-iso.sh IN.iso OUT.iso GRUBDIR
#
# Titanoboa (ublue-os/titanoboa, see live.yml) writes a UEFI-only ISO: one
# El Torito entry for EFI (the FAT image appended as GPT partition 2, with
# shim and GRUB) and /boot/grub2/grub.cfg with the menu from iso.yaml. Its
# copy of GRUB's i386-pc modules never happens (it tests the directory with
# `-f`), and it writes no BIOS boot image. VirtualBox, many other VMs and
# older PCs boot BIOS by default, so this rebuilds the ISO the way Fedora's
# own media are laid out (lorax's x86 template), adding:
#
#   /images/eltorito.img  GRUB's i386-pc El Torito core image (GRUBDIR's
#                         eltorito.img, made by grub2-mkimage with the
#                         prefix /boot/grub2), as the first, default El
#                         Torito entry: a BIOS booting the CD/DVD starts it;
#   /boot/grub2/i386-pc   GRUB's BIOS modules (GRUBDIR/i386-pc), loaded by
#                         that core image;
#   the hybrid MBR        GRUB's boot_hybrid.img (--grub2-mbr, with the core
#                         image's location patched in, --grub2-boot-info),
#                         so a USB stick written with dd boots on BIOS too.
#
# The BIOS GRUB reads the same /boot/grub2/grub.cfg Titanoboa wrote, so its
# entries and kernel arguments (rd.live.image, root=live:CDLABEL=..., the
# basic graphics entry) are the UEFI menu's. Everything else stays: the
# volume label, every file, and the EFI partition byte for byte (shim, so
# Secure Boot works as before), as the second El Torito entry and GPT
# partition 2.
#
# GRUBDIR comes from the live image itself (live.yml): its i386-pc modules
# and the eltorito.img its grub2-mkimage made, the same GRUB build as the
# EFI GRUB on the ISO. Needs xorriso, sfdisk and python3; uses free space
# next to OUT about the size of the ISO.
set -euo pipefail

in="$(realpath "${1:?usage: bios-iso.sh IN.iso OUT.iso GRUBDIR}")"
out="$(realpath -m "${2:?usage: bios-iso.sh IN.iso OUT.iso GRUBDIR}")"
grubdir="$(realpath "${3:?usage: bios-iso.sh IN.iso OUT.iso GRUBDIR}")"
for tool in xorriso sfdisk python3; do
    command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
done
for f in eltorito.img i386-pc/boot_hybrid.img i386-pc/normal.mod i386-pc/iso9660.mod i386-pc/linux.mod; do
    [[ -s "$grubdir/$f" ]] || { echo "$grubdir/$f is missing" >&2; exit 1; }
done

work="$(mktemp -d -p "$(dirname "$out")" .bios-iso.XXXXXX)"
trap 'chmod -R u+w "$work" 2>/dev/null; rm -rf "$work"' EXIT

label="$(xorriso -indev "$in" -pvd_info 2>/dev/null | sed -n 's/^Volume Id *: *//p' | head -n1)"
[[ -n $label ]] || { echo "cannot read the ISO's volume label" >&2; exit 1; }
echo "volume label: $label"

# ---- the EFI partition, as Titanoboa wrote it ------------------------------------

esp=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
read -r start size < <(sfdisk --json "$in" | python3 -c '
import json, sys
for p in json.load(sys.stdin)["partitiontable"]["partitions"]:
    if p["type"].upper() == sys.argv[1]:
        print(p["start"], p["size"])
        break
' "$esp")
[[ -n ${start:-} && -n ${size:-} ]] || { echo "no EFI system partition in $in's GPT" >&2; sfdisk --dump "$in" >&2; exit 1; }
dd if="$in" of="$work/efiboot.img" bs=512 skip="$start" count="$size" status=none
echo "EFI partition: $size sectors at $start"
# A FAT file system with shim in it, or this is not Titanoboa's layout.
head -c 512 "$work/efiboot.img" | grep -aq 'FAT' || { echo "the EFI partition holds no FAT file system" >&2; exit 1; }

# ---- the ISO's files, plus GRUB for BIOS -------------------------------------

root="$work/root"
xorriso -osirrox on -indev "$in" -extract / "$root" 2>/dev/null
chmod -R u+w "$root"
# Titanoboa's boot catalog file, if it shows; xorriso writes a new one.
rm -f "$root/boot.catalog" "$root/boot.cat"
cfg="$root/boot/grub2/grub.cfg"
[[ -s $cfg ]] || { echo "no /boot/grub2/grub.cfg on the ISO" >&2; exit 1; }
grep -q 'rd\.live\.image' "$cfg" || { echo "/boot/grub2/grub.cfg has no live entry" >&2; cat "$cfg" >&2; exit 1; }
# The BIOS menu is the UEFI menu: the same entries and kernel arguments.
for efi_cfg in "$root"/EFI/BOOT/grub.cfg "$root"/EFI/fedora/grub.cfg; do
    [[ -e $efi_cfg ]] || continue
    if ! diff <(grep -E '^[[:space:]]*(menuentry|linux|initrd|search)' "$efi_cfg") \
              <(grep -E '^[[:space:]]*(menuentry|linux|initrd|search)' "$cfg"); then
        echo "${efi_cfg#"$root"} and /boot/grub2/grub.cfg differ" >&2; exit 1
    fi
done
rm -rf "$root/boot/grub2/i386-pc"
cp -r "$grubdir/i386-pc" "$root/boot/grub2/i386-pc"
mkdir -p "$root/images"
cp "$grubdir/eltorito.img" "$root/images/eltorito.img"
echo "== /boot/grub2/grub.cfg (UEFI and BIOS)"
grep -E '^[[:space:]]*(menuentry|linux|search)' "$cfg" | sed 's/^/    /'

# ---- the new ISO ----------------------------------------------------------------

rm -f "$out"
xorriso -as mkisofs \
    -R -V "$label" -iso-level 3 \
    --grub2-mbr "$grubdir/i386-pc/boot_hybrid.img" \
    -partition_offset 16 \
    -appended_part_as_gpt \
    -append_partition 2 "$esp" "$work/efiboot.img" \
    -iso_mbr_part_type EBD0A0A2-B9E5-4433-87C0-68B6B72699C7 \
    -c boot.cat --boot-catalog-hide \
    -b images/eltorito.img \
    -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
    -eltorito-alt-boot \
    -e --interval:appended_partition_2:all:: -no-emul-boot \
    -o "$out" \
    "$root"

# ---- checks --------------------------------------------------------------------

y() { xorriso -indev "$out" "$@" 2>/dev/null; }
got="$(y -pvd_info | sed -n 's/^Volume Id *: *//p' | head -n1)"
[[ $got == "$label" ]] || { echo "the new ISO's label is '$got', not $label" >&2; exit 1; }
report="$(y -report_el_torito plain)"
echo "== boot records of the new ISO"
sed 's/^/    /' <<<"$report"
grep -Eq 'El Torito boot img : +1 +BIOS' <<<"$report" || { echo "no BIOS El Torito entry" >&2; exit 1; }
grep -Eq 'El Torito boot img : +2 +UEFI' <<<"$report" || { echo "no UEFI El Torito entry" >&2; exit 1; }
# GRUB's hybrid MBR boot code, and the EFI partition unchanged.
head -c 440 "$out" | grep -aq 'GRUB' || { echo "no GRUB boot code in the MBR" >&2; exit 1; }
read -r start2 size2 < <(sfdisk --json "$out" | python3 -c '
import json, sys
for p in json.load(sys.stdin)["partitiontable"]["partitions"]:
    if p["type"].upper() == sys.argv[1]:
        print(p["start"], p["size"])
        break
' "$esp")
cmp -s <(dd if="$out" bs=512 skip="$start2" count="$size2" status=none) "$work/efiboot.img" \
    || { echo "the new ISO's EFI partition differs from the original's" >&2; exit 1; }
echo "== partitions"
sfdisk --dump "$out" | sed 's/^/    /'
echo "BIOS and UEFI: $out ($label)"
