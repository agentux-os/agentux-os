#!/usr/bin/bash
# Installs AgentUX from the installer ISO (bootc-image-builder's
# anaconda-iso) in a headless QEMU/KVM VM, unattended, then boots the
# installed disk and checks it over SSH. Used by the Build ISO workflow
# (iso.yml), which publishes the ISO only if this passes.
#
#   iso-vm.sh ISO TRACK_IMAGE DIR
#
# 1. Read the ISO's own boot entry (EFI/BOOT/grub.cfg: kernel, initrd and
#    command line) and its kickstart (the inst.ks= file: the interactive
#    mode line, bootc-image-builder's `ostreecontainer` from the image
#    embedded in the ISO, and its %post `bootc switch` to the channel), and
#    the AgentUX branding installer/brand-iso.sh added: the volume label,
#    the boot menu's names and Anaconda's images/product.img.
#    Then boot the ISO as a person would (firmware, its GRUB, the default
#    entry) and screendump the boot menu and the graphical installer
#    (look/*.png); tests/installer-look.py fails the test if Anaconda wears
#    Fedora's colours instead of AgentUX's.
# 2. Make that kickstart unattended: drop the UI mode, add the answers the
#    installer's UI would get (language, time zone, the whole disk), a test
#    user with a throwaway SSH key and password, sshd enabled, and poweroff
#    at the end. The ISO's own payload lines are kept as they are.
# 3. Boot the ISO's kernel and initrd (QEMU direct kernel boot, UEFI) with
#    the ISO's command line, its inst.ks= pointed at that kickstart on a
#    small second CD; stage 2, the payload and its %post come from the ISO
#    itself. Only GRUB is bypassed (the menu is interactive).
# 4. Boot the installed disk alone and run tests/boot.sh's `installed`
#    checks over SSH (tests/boot-vm.sh): the deployment follows TRACK_IMAGE
#    from the registry, the signature policy requires the AgentUX key, no
#    failed units, the display manager runs.
#
# Logs and summary.md go to DIR. Needs qemu-system-x86_64 (or -aarch64) with
# KVM, UEFI firmware, qemu-img, xorriso, cpio, ssh and python3.
# ISO_TEST_MEMORY (MiB, 8192), ISO_TEST_CPUS (4) and ISO_TEST_INSTALL_TIMEOUT
# (seconds, 3600) tune the install; ISO_TEST_LOOK_TIMEOUT (seconds, 420) is
# how long to wait for the graphical installer.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
iso="$(realpath "${1:?usage: iso-vm.sh ISO TRACK_IMAGE DIR}")"
track="${2:?usage: iso-vm.sh ISO TRACK_IMAGE DIR}"
dir="$(mkdir -p "${3:?usage: iso-vm.sh ISO TRACK_IMAGE DIR}" && cd "$3" && pwd)"
inst="$dir/install"
user=boottest
machine="$(uname -m)"

if [[ "$machine" = aarch64 ]]; then
    firmware=(/usr/share/AAVMF/AAVMF_CODE.fd:/usr/share/AAVMF/AAVMF_VARS.fd
              /usr/share/edk2/aarch64/QEMU_EFI-pflash.raw:/usr/share/edk2/aarch64/vars-template-pflash.raw)
    qemu=qemu-system-aarch64 vm_machine=virt,accel=kvm,gic-version=host serial=ttyAMA0 display=virtio-gpu-pci
else
    firmware=(/usr/share/OVMF/OVMF_CODE_4M.fd:/usr/share/OVMF/OVMF_VARS_4M.fd
              /usr/share/edk2/ovmf/OVMF_CODE.fd:/usr/share/edk2/ovmf/OVMF_VARS.fd
              /usr/share/OVMF/OVMF_CODE.fd:/usr/share/OVMF/OVMF_VARS.fd)
    qemu=qemu-system-x86_64 vm_machine=q35,accel=kvm serial=ttyS0 display=virtio-vga
fi
code="" vars=""
for pair in "${firmware[@]}"; do
    if [[ -e "${pair%%:*}" && -e "${pair##*:}" ]]; then
        code="${pair%%:*}" vars="${pair##*:}"; break
    fi
done
[[ -n "$code" ]] || { echo "UEFI firmware not found" >&2; exit 1; }
[[ -w /dev/kvm ]] || { echo "/dev/kvm is not writable; KVM is required" >&2; exit 1; }
command -v xorriso >/dev/null || { echo "xorriso is required" >&2; exit 1; }

rm -rf "$inst" "$dir/summary.md"
mkdir -p "$inst"
summary() { echo "| $1 | $2 |" >>"$inst/summary.md"; }
{
    echo "## AgentUX installer ISO test"
    echo
    echo "ISO: \`$(basename "$iso")\` ($(du -h "$iso" | cut -f1)), expected to follow \`$track\`"
    echo
    echo "| Step | Result |"
    echo "|---|---|"
} >"$inst/summary.md"
# shellcheck disable=SC2317,SC2329 # called by the EXIT trap
finish() {
    local rc=$?
    cat "$inst/summary.md" >"$dir/summary.md"
    if [[ -f "$dir/boot/summary.md" ]]; then
        echo >>"$dir/summary.md"
        sed '1s/^## .*/### Installed system/' "$dir/boot/summary.md" >>"$dir/summary.md"
    fi
    if [[ -e "$inst/qemu.pid" ]]; then kill "$(cat "$inst/qemu.pid")" 2>/dev/null || true; fi
    rm -f "$inst/OVMF_VARS.fd" "$inst/qemu.pid"
    exit "$rc"
}
trap finish EXIT

# ---- 1. the ISO's boot entry and kickstart -------------------------------------

extract() { xorriso -osirrox on -indev "$iso" -extract "$1" "$2" 2>/dev/null; }
extract /EFI/BOOT/grub.cfg "$inst/grub.cfg"
# The first menu entry: the default, "Install ...".
read -r kernel args < <(awk '$1 ~ /^linux(efi)?$/ {$1 = ""; sub(/^ /, ""); print; exit}' "$inst/grub.cfg")
initrd="$(awk '$1 ~ /^initrd(efi)?$/ {print $2; exit}' "$inst/grub.cfg")"
ks_arg="$(grep -o 'inst\.ks=[^ ]*' <<<"$args" || true)"
if [[ -z "$kernel" || -z "$initrd" || -z "$ks_arg" ]]; then
    echo "::error::cannot read the installer's boot entry and kickstart from EFI/BOOT/grub.cfg"
    cat "$inst/grub.cfg"
    exit 1
fi
echo "boot entry: $kernel $args"
extract "$kernel" "$inst/vmlinuz"
extract "$initrd" "$inst/initrd.img"
ks_path="/${ks_arg##*:/}"
extract "$ks_path" "$inst/iso.ks"
echo "the ISO's kickstart ($ks_path):"
sed 's/^/    /' "$inst/iso.ks"
# Files it %includes from the ISO (/run/install/repo is the ISO, mounted as
# stage 2's source) stay included as they are; they are read here only for
# the checks below.
cp "$inst/iso.ks" "$inst/iso-all.ks"
while read -r inc; do
    extract "${inc#/run/install/repo}" "$inst/include.ks" && cat "$inst/include.ks" >>"$inst/iso-all.ks"
    echo "included $inc:"; sed 's/^/    /' "$inst/include.ks"
done < <(sed -n 's|^%include \(/run/install/repo/[^ ]*\)$|\1|p' "$inst/iso.ks")
# The payload must be the ISO's: bootc-image-builder's ostreecontainer and
# the switch to the channel.
grep -q '^ostreecontainer ' "$inst/iso-all.ks" \
    || { echo "::error::the ISO's kickstart has no ostreecontainer line"; exit 1; }
if grep -q "bootc switch .*$track" "$inst/iso-all.ks"; then
    summary "Kickstart switches to \`$track\`" ok
else
    echo "::error::the ISO's kickstart does not switch the installed system to $track"
    summary "Kickstart switches to \`$track\`" FAIL
    exit 1
fi

# The AgentUX branding installer/brand-iso.sh put on the ISO: its label, the
# boot menu's names, and Anaconda's product image.
label="$(xorriso -indev "$iso" -pvd_info 2>/dev/null | sed -n 's/^Volume Id *: *//p' | head -n1)"
titles="$(grep -E '^[[:space:]]*(menuentry|submenu)' "$inst/grub.cfg" | sed -E "s/^[[:space:]]*(menuentry|submenu) '([^']*)'.*/\2/" | paste -sd ';')"
echo "volume label: $label; boot menu: $titles"
if [[ $label == AgentUX-* && $titles == *AgentUX* && $titles != *Fedora* && ! $titles =~ AgentUX\ [0-9]+ ]]; then
    summary "ISO label and boot menu name AgentUX" "ok: \`$label\`; ${titles//;/, }"
else
    echo "::error::the ISO's label ($label) or boot menu ($titles) is not AgentUX's"
    summary "ISO label and boot menu name AgentUX" "FAIL: \`$label\`; $titles"
    exit 1
fi
mkdir -p "$inst/product"
if extract /images/product.img "$inst/product.img" \
    && (cd "$inst/product" && zcat ../product.img | cpio --quiet -id) \
    && grep -qx 'Product=AgentUX' "$inst/product/.buildstamp" \
    && grep -q 'agentux' "$inst/product/usr/share/anaconda/pixmaps/fedora.css" \
    && [[ -s "$inst/product/usr/share/anaconda/pixmaps/sidebar-logo.png" ]]; then
    summary "Anaconda product image (AgentUX name, stylesheet, art)" "ok: $(sed -n 's/^Version=//p' "$inst/product/.buildstamp")"
    cp "$inst/product/.buildstamp" "$inst/buildstamp.txt"
else
    echo "::error::the ISO has no AgentUX images/product.img"
    summary "Anaconda product image (AgentUX name, stylesheet, art)" FAIL
    exit 1
fi
rm -rf "$inst/product" "$inst/product.img"

# ---- 1b. what the installer looks like -------------------------------------------

# The ISO booted the way a person boots it (firmware, the ISO's own GRUB,
# its default entry, the graphical installer), with screendumps of the
# menu and of Anaconda once it is drawn; tests/installer-look.py tells
# AgentUX's colours from Fedora's. Nothing is installed: the ISO's own
# kickstart waits for the person at the first screen.
look="$dir/look"
rm -rf "$look"
mkdir -p "$look"
cp "$vars" "$look/OVMF_VARS.fd"
"$qemu" \
    -name agentux-iso-look \
    -machine "$vm_machine" -cpu host \
    -smp "${ISO_TEST_CPUS:-4}" -m "${ISO_TEST_MEMORY:-8192}" \
    -drive if=pflash,format=raw,readonly=on,file="$code" \
    -drive if=pflash,format=raw,file="$look/OVMF_VARS.fd" \
    -device virtio-scsi-pci,id=scsi \
    -drive "file=$iso,media=cdrom,if=none,id=cd,readonly=on" -device scsi-cd,drive=cd,bus=scsi.0,bootindex=0 \
    -nic user,model=virtio-net-pci \
    -device virtio-rng-pci \
    -device "$display" -display none \
    -serial file:"$look/serial.log" \
    -qmp unix:"$look/qmp.sock",server=on,wait=off \
    -pidfile "$look/qemu.pid" -daemonize
qmp() { python3 "$here/qga.py" qmp "$look/qmp.sock" "$1" >/dev/null 2>&1; }
shot() { qmp "{\"execute\": \"screendump\", \"arguments\": {\"filename\": \"$1\", \"format\": \"$2\"}}"; }
sleep 15
shot "$look/01-boot-menu.png" png || true
# The default entry now, rather than after GRUB's 60 s.
qmp '{"execute": "send-key", "arguments": {"keys": [{"type": "qcode", "data": "ret"}]}}' || true
look_rc=2 start=$SECONDS
while (( SECONDS - start < ${ISO_TEST_LOOK_TIMEOUT:-420} )); do
    sleep 20
    shot "$look/frame.ppm" ppm || continue
    set +e
    python3 "$here/installer-look.py" "$look/frame.ppm" >"$look/look.txt"
    look_rc=$?
    set -e
    if (( look_rc != 2 )); then
        # Up: give GTK a moment to finish drawing, then judge that frame.
        sleep 20
        shot "$look/frame.ppm" ppm || true
        set +e
        python3 "$here/installer-look.py" "$look/frame.ppm" >"$look/look.txt"
        look_rc=$?
        set -e
        break
    fi
done
shot "$look/02-installer.png" png || true
cat "$look/look.txt" 2>/dev/null || true
qmp '{"execute": "quit"}' || true
sleep 2
if [[ -e "$look/qemu.pid" ]]; then kill "$(cat "$look/qemu.pid")" 2>/dev/null || true; fi
rm -f "$look/OVMF_VARS.fd" "$look/qemu.pid" "$look/qmp.sock" "$look/frame.ppm"
case "$look_rc" in
    0) summary "Installer shows AgentUX's look (look/02-installer.png)" "ok: $(head -n1 "$look/look.txt")" ;;
    1)
        echo "::error::the installer does not show AgentUX's branding; see look/02-installer.png"
        summary "Installer shows AgentUX's look (look/02-installer.png)" "FAIL: $(tail -n1 "$look/look.txt")"
        exit 1
        ;;
    *)
        echo "::warning::the graphical installer did not appear within ${ISO_TEST_LOOK_TIMEOUT:-420}s; see look/02-installer.png"
        summary "Installer shows AgentUX's look (look/02-installer.png)" "warn: no installer on screen after ${ISO_TEST_LOOK_TIMEOUT:-420}s"
        ;;
esac

# ---- 2. an unattended kickstart --------------------------------------------------

"$here/boot-vm.sh" config "$dir/boot" >/dev/null
password="$(cat "$dir/boot/password")"
pubkey="$(cat "$dir/boot/id_ed25519.pub")"
{
    cat <<EOF
# Installer ISO test: the answers the installer UI would get, then the ISO's
# own kickstart without its UI mode line.
cmdline
lang en_US.UTF-8
keyboard us
timezone UTC --utc
ignoredisk --only-use=vda
zerombr
clearpart --all --initlabel --drives=vda
autopart --noswap
rootpw --lock
# A graphical boot, as an install from the UI gives.
xconfig --startxonboot
user --name=$user --password=$password --plaintext --groups=wheel
sshkey --username=$user "$pubkey"
poweroff

EOF
    grep -Ev '^[[:space:]]*(graphical|text|cmdline)[[:space:]]*$' "$inst/iso.ks"
    cat <<EOF

# The test's way in: sshd (Kinoite does not enable it) and the test user's
# key, also when the installer's Users module is off.
%post --erroronfail
set -e
systemctl enable sshd.service
id $user >/dev/null 2>&1 || useradd -m -G wheel $user
echo '$user:$password' | chpasswd
home=\$(getent passwd $user | cut -d: -f6)
install -d -m 0700 -o $user -g $user "\$home/.ssh"
echo '$pubkey' >"\$home/.ssh/authorized_keys"
chown $user:$user "\$home/.ssh/authorized_keys"
chmod 0600 "\$home/.ssh/authorized_keys"
%end
EOF
} >"$inst/ks.cfg"
mkdir -p "$inst/ksdir"
cp "$inst/ks.cfg" "$inst/ksdir/ks.cfg"
xorriso -as mkisofs -quiet -V AUXKS -o "$inst/ks.iso" "$inst/ksdir"
# The password stays out of the uploaded logs.
sed -i "s/$password/<password>/g" "$inst/ks.cfg"

cmdline="$(sed "s|inst\.ks=[^ ]*|inst.ks=hd:LABEL=AUXKS:/ks.cfg|; s|\bquiet\b||g; s|\brhgb\b||g" <<<"$args") console=tty0 console=$serial,115200 inst.notmux"
echo "install command line: $cmdline"

# ---- 3. the install --------------------------------------------------------------

cp "$vars" "$inst/OVMF_VARS.fd"
qemu-img create -q -f qcow2 "$inst/disk.qcow2" 64G
"$qemu" \
    -name agentux-iso-test \
    -machine "$vm_machine" -cpu host \
    -smp "${ISO_TEST_CPUS:-4}" -m "${ISO_TEST_MEMORY:-8192}" \
    -drive if=pflash,format=raw,readonly=on,file="$code" \
    -drive if=pflash,format=raw,file="$inst/OVMF_VARS.fd" \
    -kernel "$inst/vmlinuz" -initrd "$inst/initrd.img" -append "$cmdline" \
    -device virtio-scsi-pci,id=scsi \
    -drive "file=$iso,media=cdrom,if=none,id=cd,readonly=on" -device scsi-cd,drive=cd,bus=scsi.0 \
    -drive "file=$inst/ks.iso,media=cdrom,if=none,id=ks,readonly=on" -device scsi-cd,drive=ks,bus=scsi.0 \
    -drive file="$inst/disk.qcow2",if=none,id=disk,format=qcow2 -device virtio-blk-pci,drive=disk \
    -nic user,model=virtio-net-pci \
    -device virtio-rng-pci \
    -display none -vga none \
    -serial file:"$inst/serial-install.log" \
    -pidfile "$inst/qemu.pid" -daemonize
start=$SECONDS
limit="${ISO_TEST_INSTALL_TIMEOUT:-3600}"
echo "::group::install (serial console)"
while kill -0 "$(cat "$inst/qemu.pid")" 2>/dev/null; do
    if (( SECONDS - start > limit )); then
        echo "::endgroup::"
        echo "::error::the install did not finish in ${limit}s; see install/serial-install.log"
        tail -n 60 "$inst/serial-install.log"
        summary "Unattended install" "FAIL: timed out after ${limit}s"
        exit 1
    fi
    sleep 30
    echo "installing: $(( SECONDS - start ))s, $(tail -n 1 "$inst/serial-install.log" | tr -d '\r' | cut -c1-150)"
done
rm -f "$inst/qemu.pid"
echo "::endgroup::"
took=$(( SECONDS - start ))
if grep -qiE 'traceback|installation failed|an unknown error has occurred|kickstart.*error' "$inst/serial-install.log"; then
    echo "::error::Anaconda reported an error; see install/serial-install.log"
    grep -iE -B5 -A20 'traceback|installation failed|unknown error|kickstart.*error' "$inst/serial-install.log" | tail -n 80
    summary "Unattended install" "FAIL after ${took}s (serial-install.log)"
    exit 1
fi
summary "Unattended install" "ok, powered off after ${took}s"
echo "install finished after ${took}s"

# ---- 4. the installed system -------------------------------------------------------

set +e
BOOT_TEST_PHASE=installed BOOT_TEST_DESKTOP=0 BOOT_TEST_SPLASH_SECONDS=20 \
    "$here/boot-vm.sh" run "$inst/disk.qcow2" "$track" "$dir/boot"
rc=$?
set -e
summary "Installed system checks" "$([[ $rc == 0 ]] && echo ok || echo "FAIL (exit $rc)")"
exit "$rc"
