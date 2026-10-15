#!/usr/bin/bash
# Boots the AgentUX live ISO in a headless QEMU/KVM VM and tests it through
# the QEMU guest agent the live system ships (tests/qga.py runs
# tests/live.sh in it as root). Used by the Live ISO workflow (live.yml).
#
#   live-vm.sh ISO DIR
#
# 1. Boot the ISO (UEFI, or BIOS with LIVE_TEST_FIRMWARE=bios; from the CD,
#    the VM's empty disk behind it), with screendumps every 2 s of the first
#    two minutes (GRUB, the boot splash) in DIR/boot/. With BIOS, the ISO is
#    first booted as a USB stick written with dd (its hybrid MBR) up to the
#    guest agent, with its frames in DIR/usb-boot/.
# 2. Wait for the live user's autologin session and check it (tests/live.sh
#    checks): Plasma and the cockpit, agentuxd with fake agents answering
#    `aux ps` with the demo runs, no first-login downloads; the installer
#    launcher only warns. Screenshots of the desktop, of the demo after
#    approving its waiting run, and of the installer opened from
#    "Install AgentUX" (best effort).
# 3. With LIVE_TEST_INSTALL=1 (the default): install to the VM's disk with
#    Anaconda from the live system, unattended but with the live installer's
#    own payload, check the installed deployment (it tracks the channel the
#    ISO was built for, LIVE_TRACK_IMAGE, and nothing live-only is in it), then boot the disk alone and screenshot
#    its first boot (with the same firmware: an install on a BIOS VM must
#    leave a BIOS boot partition and GRUB in the disk's MBR). The install
#    needs the VM to reach ghcr.io; if it fails, the job only warns, but a
#    wrong installed system fails it.
#
# Logs, screenshots and summary.md go to DIR. Needs qemu-system-x86_64 (or
# -aarch64) with KVM, UEFI firmware (ovmf / qemu-efi-aarch64; for
# LIVE_TEST_FIRMWARE=bios, QEMU's default SeaBIOS), qemu-img and python3.
# LIVE_TEST_MEMORY (MiB, default 12288: the install from the live system
# runs in RAM) and LIVE_TEST_CPUS (4) size the VM.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
iso="$(realpath "${1:?usage: live-vm.sh ISO DIR}")"
dir="$(mkdir -p "${2:?usage: live-vm.sh ISO DIR}" && cd "$2" && pwd)"
machine="$(uname -m)"
system_rc=1 install_rc=skipped usb_rc=0
firmware_mode="${LIVE_TEST_FIRMWARE:-uefi}"
case "$firmware_mode" in
    uefi) ;;
    bios) [[ "$(uname -m)" == x86_64 ]] || { echo "BIOS boot is x86_64 only" >&2; exit 2; } ;;
    *) echo "LIVE_TEST_FIRMWARE must be uefi or bios" >&2; exit 2 ;;
esac

if [[ "$machine" = aarch64 ]]; then
    firmware=(/usr/share/AAVMF/AAVMF_CODE.fd:/usr/share/AAVMF/AAVMF_VARS.fd
              /usr/share/edk2/aarch64/QEMU_EFI-pflash.raw:/usr/share/edk2/aarch64/vars-template-pflash.raw)
    qemu=qemu-system-aarch64 vm_machine=virt,accel=kvm,gic-version=host display=virtio-gpu-pci,xres=1920,yres=1080
else
    firmware=(/usr/share/OVMF/OVMF_CODE_4M.fd:/usr/share/OVMF/OVMF_VARS_4M.fd
              /usr/share/edk2/ovmf/OVMF_CODE.fd:/usr/share/edk2/ovmf/OVMF_VARS.fd
              /usr/share/OVMF/OVMF_CODE.fd:/usr/share/OVMF/OVMF_VARS.fd)
    qemu=qemu-system-x86_64 vm_machine=q35,accel=kvm display=virtio-vga,xres=1920,yres=1080
fi
code="" vars=""
for pair in "${firmware[@]}"; do
    if [[ -e "${pair%%:*}" && -e "${pair##*:}" ]]; then
        code="${pair%%:*}" vars="${pair##*:}"; break
    fi
done
[[ -n "$code" || "$firmware_mode" == bios ]] || { echo "UEFI firmware not found" >&2; exit 1; }
[[ -w /dev/kvm ]] || { echo "/dev/kvm is not writable; KVM is required" >&2; exit 1; }

rm -rf "${dir:?}/boot" "${dir:?}/usb-boot" "${dir:?}/installed-boot"
rm -f "$dir"/*.png "$dir"/*.log "$dir"/*.txt "$dir/summary.md" "$dir/summary.extra"
# UEFI: OVMF in pflash. BIOS: no pflash, so QEMU's default firmware, SeaBIOS.
firmware_args=()
if [[ "$firmware_mode" == uefi ]]; then
    cp "$vars" "$dir/OVMF_VARS.fd"
    firmware_args=(-drive if=pflash,format=raw,readonly=on,file="$code"
                   -drive if=pflash,format=raw,file="$dir/OVMF_VARS.fd")
fi
qemu-img create -q -f qcow2 "$dir/disk.qcow2" 64G

# start_vm [cd|usb]: the VM, with the ISO as its CD or as a USB stick (the
# ISO's bytes as a disk, as dd writes them; writes go to a throwaway
# snapshot) when asked, the disk always.
start_vm() {
    local cd_args=()
    if [[ "${1:-}" == cd ]]; then
        cd_args=(-drive "file=$iso,media=cdrom,if=none,id=cd,readonly=on"
                 -device "scsi-cd,drive=cd,bus=scsi.0,bootindex=0")
    elif [[ "${1:-}" == usb ]]; then
        cd_args=(-device qemu-xhci,id=xhci
                 -drive "file=$iso,format=raw,if=none,id=usb,snapshot=on"
                 -device "usb-storage,bus=xhci.0,drive=usb,removable=on,bootindex=0")
    fi
    rm -f "$dir/qmp.sock" "$dir/qga.sock"
    "$qemu" \
        -name agentux-live-test \
        -machine "$vm_machine" -cpu host \
        -smp "${LIVE_TEST_CPUS:-4}" -m "${LIVE_TEST_MEMORY:-12288}" \
        "${firmware_args[@]}" \
        -device virtio-scsi-pci,id=scsi \
        "${cd_args[@]}" \
        -drive file="$dir/disk.qcow2",if=none,id=disk,format=qcow2 \
        -device virtio-blk-pci,drive=disk,bootindex=1 \
        -device "$display" -display none \
        -nic user,model=virtio-net-pci \
        -device virtio-rng-pci \
        -device virtio-serial-pci \
        -chardev socket,path="$dir/qga.sock",server=on,wait=off,id=qga0 \
        -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0 \
        -serial file:"$dir/serial${1:+-$1}.log" \
        -qmp unix:"$dir/qmp.sock",server=on,wait=off \
        -pidfile "$dir/qemu.pid" -daemonize
}

stop_vm() {
    if [[ -n "${capture_pid:-}" ]]; then kill "$capture_pid" 2>/dev/null || true; capture_pid=""; fi
    if [[ -S "$dir/qmp.sock" ]]; then
        python3 "$here/qga.py" qmp "$dir/qmp.sock" '{"execute": "quit"}' 2>/dev/null || true
    fi
    sleep 2
    if [[ -e "$dir/qemu.pid" ]]; then
        kill "$(cat "$dir/qemu.pid")" 2>/dev/null || true
    fi
    rm -f "$dir/qemu.pid"
}

# shellcheck disable=SC2317 # called by the EXIT trap
cleanup() {
    stop_vm
    rm -f "$dir/disk.qcow2" "$dir/OVMF_VARS.fd" "$dir/qmp.sock" "$dir/qga.sock"
}
trap cleanup EXIT

screenshot() {
    local png="$dir/$1.png"
    if python3 "$here/qga.py" qmp "$dir/qmp.sock" \
        "{\"execute\": \"screendump\", \"arguments\": {\"filename\": \"$png\", \"format\": \"png\"}}" \
        && [[ -s "$png" ]]; then
        echo "screenshot $png"
    else
        echo "::warning::screenshot $1 failed"
    fi
}

# Screendumps every 2 s for $2 seconds into DIR/$1, in the background.
capture_frames() {
    mkdir -p "$dir/$1"
    (
        local i=0 end=$(( SECONDS + $2 ))
        while (( SECONDS < end )); do
            python3 "$here/qga.py" qmp "$dir/qmp.sock" \
                "{\"execute\": \"screendump\", \"arguments\": {\"filename\": \"$dir/$1/$(printf %03d "$i").png\", \"format\": \"png\"}}" \
                2>/dev/null || true
            i=$(( i + 1 ))
            sleep 2
        done
    ) &
    capture_pid=$!
}

wait_agent() {
    local start=$SECONDS
    until python3 "$here/qga.py" ping "$dir/qga.sock"; do
        if (( SECONDS - start > $1 )) || ! kill -0 "$(cat "$dir/qemu.pid" 2>/dev/null)" 2>/dev/null; then
            return 1
        fi
        sleep 5
    done
    waited=$(( SECONDS - start ))
}

# guest PHASE TIMEOUT: runs tests/live.sh's PHASE in the VM.
guest() {
    python3 "$here/qga.py" exec "$dir/qga.sock" "$2" "LIVE_PHASE=$1
$(cat "$here/live.sh")"
}

# guest_cmd TIMEOUT SCRIPT: any command in the VM, as root.
guest_cmd() {
    python3 "$here/qga.py" exec "$dir/qga.sock" "$1" "$2"
}

summary_line() { echo "| $1 | $2 |" >>"$dir/summary.md"; }

summary_phase() {
    local name="$1" rc="$2" log="$3" metric
    summary_line "$name" "$([[ "$rc" == 0 ]] && echo ok || echo "FAIL (exit $rc)"): $(grep -c '^ok ' "$log" || true) ok, $(grep -c '^FAIL ' "$log" || true) failed, $(grep -c '^warn ' "$log" || true) warnings"
    while IFS= read -r metric; do
        summary_line "${metric%%: *}" "${metric#*: }"
    done < <(sed -n 's/^metric  //p' "$log")
    {
        echo
        echo "<details><summary>$name</summary>"
        echo
        echo '```'
        grep -E '^(ok|FAIL|warn|metric) |^== ' "$log" || true
        echo '```'
        echo "</details>"
    } >>"$dir/summary.extra"
}

{
    echo "## AgentUX live ISO test ($([[ $firmware_mode == bios ]] && echo "BIOS: SeaBIOS" || echo UEFI))"
    echo
    echo "ISO: \`$(basename "$iso")\` ($(du -h "$iso" | cut -f1))"
    echo
    echo "| Step | Result |"
    echo "|---|---|"
} >"$dir/summary.md"

finish() {
    [[ -e "$dir/summary.extra" ]] && cat "$dir/summary.extra" >>"$dir/summary.md"
    rm -f "$dir/summary.extra"
    local f names=()
    for f in "$dir"/*.png; do [[ -e "$f" ]] && names+=("$(basename "$f")"); done
    printf '\nScreenshots (artifact): %s; boot frames in boot/%s\n' "${names[*]}" \
        "$([[ $firmware_mode == bios ]] && echo ", usb-boot/ (USB stick) and installed-boot/")" >>"$dir/summary.md"
}

# ---- 0. BIOS: the ISO as a dd-written USB stick ------------------------------

if [[ "$firmware_mode" == bios ]]; then
    # SeaBIOS boots the stick's hybrid MBR (GRUB's boot_hybrid.img), which
    # loads the El Torito core image; the live system then finds its root by
    # the label on the stick. Up to the guest agent, then the CD path below.
    start_vm usb
    capture_frames usb-boot 120
    if wait_agent "${LIVE_TEST_BOOT_TIMEOUT:-900}"; then
        cmdline="$(guest_cmd 30 'cat /proc/cmdline; test ! -d /sys/firmware/efi && echo "(no EFI: booted by BIOS)"' 2>/dev/null || true)"
        echo "USB stick (BIOS): guest agent up after ${waited}s; $cmdline"
        if [[ "$cmdline" == *rd.live.image*"booted by BIOS"* ]]; then
            summary_line "BIOS boot from the ISO written to a USB stick" "ok after ${waited}s (usb-boot/, 00-usb-bios-live.png)"
        else
            summary_line "BIOS boot from the ISO written to a USB stick" "FAIL: not a BIOS-booted live system ($cmdline)"
            usb_rc=1
        fi
        sleep 30
        screenshot 00-usb-bios-live
    else
        echo "::error::the ISO written to a USB stick did not boot with BIOS; see usb-boot/ and serial-usb.log"
        screenshot 00-usb-bios-no-agent
        summary_line "BIOS boot from the ISO written to a USB stick" "FAIL (usb-boot/)"
        usb_rc=1
    fi
    stop_vm
fi

# ---- 1. boot ---------------------------------------------------------------

start_vm cd
capture_frames boot 120
if ! wait_agent "${LIVE_TEST_BOOT_TIMEOUT:-900}"; then
    echo "::error::the live system's guest agent never answered; see boot/ and serial-cd.log"
    screenshot boot-no-agent
    summary_line "Boot to guest agent" "FAIL"
    finish
    exit 1
fi
summary_line "Boot from the CD to guest agent ($firmware_mode)" "ok after ${waited}s"
echo "guest agent up after ${waited}s"

# ---- 2. live session ---------------------------------------------------------

echo "::group::live session"
if guest session 720 | tee "$dir/live-session.log"; then
    summary_line "Autologin into the live session" "ok"
else
    summary_line "Autologin into the live session" "FAIL (see live-session.log)"
fi
echo "::endgroup::"
# Let Plasma, the cockpit and the demo settle.
sleep 45
screenshot 01-live-desktop

echo "::group::live checks"
set +e
guest checks 900 | tee "$dir/live-checks.log"
system_rc=${PIPESTATUS[0]}
set -e
echo "::endgroup::"
summary_phase "Live session checks" "$system_rc" "$dir/live-checks.log"
screenshot 02-live-desktop-later

# The desktop behind the cockpit: the launchers and the note (Plasma's Show
# Desktop, toggled on and off again).
show_desktop() {
    # shellcheck disable=SC2016 # expanded in the VM
    guest_cmd 30 'uid=$(id -u liveuser); runuser -u liveuser -- env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus busctl --user call org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component invokeShortcut s "Show Desktop"' \
        >/dev/null || echo "::warning::could not toggle Show Desktop"
}
show_desktop
sleep 3
screenshot 02-live-desktop-shown
show_desktop

# The demo's waiting run, approved: the cockpit shows it move through the
# pipeline.
guest approve 120 | tee "$dir/live-approve.log" || true
sleep 8
screenshot 03-demo-running
sleep 30
screenshot 04-demo-later

# The installer, as "Install AgentUX" starts it (best effort).
echo "::group::installer launcher"
# shellcheck disable=SC2016 # expanded in the VM
guest_cmd 60 'uid=$(id -u liveuser); runuser -u liveuser -- env XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus systemd-run --user --unit=live-test-installer --collect /usr/libexec/agentux/live-install' \
    || echo "::warning::could not start Install AgentUX"
sleep 75
screenshot 05-installer
guest_cmd 60 'ps -eo pid,user,args | grep -E "[a]naconda|[l]iveinst|[p]kexec" || echo "no installer process"' | tee "$dir/installer-processes.txt" || true
if grep -q anaconda "$dir/installer-processes.txt"; then
    summary_line "Install AgentUX opens the installer (best effort)" "ok"
else
    echo "::warning::the installer did not start from Install AgentUX; see 05-installer.png"
    summary_line "Install AgentUX opens the installer (best effort)" "warn: no anaconda process (05-installer.png)"
fi
guest_cmd 60 'pkill -f "anaconda|liveinst" || true; sleep 5; pkill -9 -f "anaconda|liveinst" || true; rm -rf /run/anaconda /tmp/anaconda*.log /tmp/packaging.log' >/dev/null 2>&1 || true
echo "::endgroup::"

guest_cmd 120 'journalctl --no-pager -b' >"$dir/journal-live.log" 2>&1 || true

# ---- 3. install --------------------------------------------------------------

if [[ "${LIVE_TEST_INSTALL:-1}" == 1 ]]; then
    echo "::group::install from the live system"
    set +e
    install_start=$SECONDS
    guest install 300 | tee "$dir/install.log"
    install_rc=${PIPESTATUS[0]}
    if [[ "$install_rc" == 0 ]]; then
        # Poll: each check is a short guest agent call. At the end of a
        # kickstart install Anaconda halts the system (the kickstart default),
        # so the agent going away for good also ends the wait.
        deadline=$(( SECONDS + 3600 )) gone=0
        while (( SECONDS < deadline && gone < 6 )); do
            out="$(guest install-done 60 2>&1)"; rc=$?
            echo "${out##*$'\n'}"
            [[ "$rc" == 0 ]] && break
            if [[ "$out" == *Traceback* || "$out" == *qga:* ]]; then gone=$(( gone + 1 )); else gone=0; fi
            sleep 30
        done
        # Timed from the host: the live system may be gone by now.
        echo "metric  install time: $(( SECONDS - install_start ))s" | tee -a "$dir/install.log"
        screenshot 05b-after-install
        if ! guest install-result 120 >"$dir/install-result.log" 2>&1; then
            # A guest that halted, or a FAIL line: keep only the guest's FAIL lines.
            grep -q '^FAIL ' "$dir/install-result.log" \
                || echo "      the guest agent is gone: Anaconda halted the live system at the end, as kickstart installs do" >>"$dir/install-result.log"
        fi
        if grep -q '^FAIL\|^ok\|^      ' "$dir/install-result.log"; then
            grep -v '^Traceback\|^  File \|^    [^ ]\|^[A-Za-z.]*Error:' "$dir/install-result.log" | tee -a "$dir/install.log"
        fi
        rm -f "$dir/install-result.log"
        guest_cmd 60 'cat /tmp/anaconda.log /tmp/packaging.log /tmp/program.log 2>/dev/null' >"$dir/anaconda.log" 2>&1
        guest_cmd 60 'cat /tmp/storage.log /tmp/dbus.log 2>/dev/null' >"$dir/anaconda-storage.log" 2>&1
    fi
    set -e
    echo "::endgroup::"
    stop_vm

    # The installed disk, from the host: whether the live system was still
    # there to report on it or not, the disk says what got installed.
    echo "::group::installed system"
    set +e
    sudo modprobe nbd max_part=16
    sudo qemu-nbd --connect=/dev/nbd0 "$dir/disk.qcow2"
    sleep 3
    sudo partprobe /dev/nbd0 2>/dev/null
    lsblk -f /dev/nbd0
    # The channel the installed system must follow: LIVE_TRACK_IMAGE (what
    # live.yml built the ISO with), or the ISO's variant's :latest.
    track_image="${LIVE_TRACK_IMAGE:-}"
    if [[ -z "$track_image" ]]; then
        track_image=ghcr.io/agentux-os/agentux:latest
        [[ "$(basename "$iso")" == *hyprland* ]] && track_image=ghcr.io/agentux-os/agentux-hyprland:latest
    fi
    sudo env LIVE_PHASE=verify LIVE_TARGET=/dev/nbd0 LIVE_TRACK_IMAGE="$track_image" LIVE_FIRMWARE="$firmware_mode" \
        bash "$here/live.sh" | tee "$dir/install-verify.log"
    verify_rc=${PIPESTATUS[0]}
    sudo qemu-nbd --disconnect /dev/nbd0 >/dev/null
    set -e
    echo "::endgroup::"
    if [[ "$install_rc" != 0 ]] || grep -q '^FAIL no ostree deployment' "$dir/install-verify.log"; then
        echo "::warning::installing from the live system failed; see install.log and anaconda.log"
        echo "FAIL no AgentUX deployment on the disk after the install" >>"$dir/install.log"
        summary_phase "Install from the live system (best effort)" 1 "$dir/install.log"
    else
        # The disk decides: an install that left a deployment finished,
        # whatever the guest could still report.
        sed -i '/^FAIL anaconda failed (exit none)/d' "$dir/install.log"
        echo "ok   AgentUX deployment on the disk" >>"$dir/install.log"
        summary_phase "Install from the live system" "$(grep -q '^FAIL ' "$dir/install.log" && echo 1 || echo 0)" "$dir/install.log"
        summary_phase "Installed system checks" "$verify_rc" "$dir/install-verify.log"
        (( verify_rc == 0 )) || system_rc=1

        # The installed disk alone: its first boot (plasma-setup's wizard).
        start_vm
        capture_frames installed-boot 90
        sleep 240
        screenshot 06-installed-first-boot
        summary_line "Installed system first boot" "see 06-installed-first-boot.png"
    fi
fi

finish
(( usb_rc == 0 )) || system_rc=1
exit "$system_rc"
