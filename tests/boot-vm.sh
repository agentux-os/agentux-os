#!/usr/bin/bash
# Boots an AgentUX disk image in a headless QEMU/KVM VM and runs tests/boot.sh
# in it over SSH. Used by the Boot test workflow and `just boot-test`.
#
#   boot-vm.sh config DIR
#       Write a throwaway SSH key and password and a bootc-image-builder
#       config (DIR/config.toml) that adds the test user with them.
#   boot-vm.sh run DISK IMAGE DIR
#       Boot DISK (a qcow2 built with that config) on a copy-on-write overlay,
#       check it booted IMAGE, then reboot into Plasma with autologin for the
#       desktop checks. Logs, screenshots and summary.md go to DIR.
#
# Needs qemu-system-x86_64 with KVM, qemu-img, OVMF, ssh and python3. Only the
# system checks decide the exit status; the desktop ones are best effort.
set -euo pipefail

user=boottest
here="$(cd "$(dirname "$0")" && pwd)"

config() {
    local dir="$1"
    mkdir -p "$dir"
    rm -f "$dir/id_ed25519" "$dir/id_ed25519.pub"
    ssh-keygen -q -t ed25519 -N '' -C agentux-boot-test -f "$dir/id_ed25519"
    head -c 18 /dev/urandom | base64 | tr -d '/+=' >"$dir/password"
    # sshd is not enabled in Kinoite; the kernel argument starts it for this
    # disk only. The serial console gets systemd's boot messages too.
    cat >"$dir/config.toml" <<EOF
[[customizations.user]]
name = "$user"
password = "$(cat "$dir/password")"
key = "$(cat "$dir/id_ed25519.pub")"
groups = ["wheel"]

[customizations.kernel]
append = "systemd.wants=sshd.service console=tty0 console=ttyS0,115200"
EOF
    echo "wrote $dir/config.toml"
}

run() {
    local disk="$1" image="$2"
    dir="$(mkdir -p "$3" && cd "$3" && pwd)"
    port="${BOOT_TEST_SSH_PORT:-2222}"
    local code="" vars=""
    for pair in /usr/share/OVMF/OVMF_CODE_4M.fd:/usr/share/OVMF/OVMF_VARS_4M.fd \
                /usr/share/edk2/ovmf/OVMF_CODE.fd:/usr/share/edk2/ovmf/OVMF_VARS.fd \
                /usr/share/OVMF/OVMF_CODE.fd:/usr/share/OVMF/OVMF_VARS.fd; do
        if [[ -e "${pair%%:*}" && -e "${pair##*:}" ]]; then
            code="${pair%%:*}" vars="${pair##*:}"; break
        fi
    done
    [[ -n "$code" ]] || { echo "OVMF not found; install ovmf (Debian/Ubuntu) or edk2-ovmf (Fedora)" >&2; exit 1; }
    [[ -w /dev/kvm ]] || { echo "/dev/kvm is not writable; KVM is required" >&2; exit 1; }

    cp "$vars" "$dir/OVMF_VARS.fd"
    rm -f "$dir/vm.qcow2" "$dir"/*.png "$dir"/*.log "$dir"/*.txt "$dir/summary.md"
    qemu-img create -q -f qcow2 -F qcow2 -b "$(realpath "$disk")" "$dir/vm.qcow2"
    qemu-system-x86_64 \
        -name agentux-boot-test \
        -machine q35,accel=kvm -cpu host \
        -smp "${BOOT_TEST_CPUS:-4}" -m "${BOOT_TEST_MEMORY:-8192}" \
        -drive if=pflash,format=raw,readonly=on,file="$code" \
        -drive if=pflash,format=raw,file="$dir/OVMF_VARS.fd" \
        -drive file="$dir/vm.qcow2",if=virtio,format=qcow2 \
        -device virtio-vga -display none \
        -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:"$port"-:22 \
        -device virtio-rng-pci \
        -serial file:"$dir/serial.log" \
        -qmp unix:"$dir/qmp.sock",server=on,wait=off \
        -pidfile "$dir/qemu.pid" -daemonize
    trap cleanup EXIT

    system_rc=1 desktop_rc=skipped
    summary_init "$image"
    if ! wait_ssh "${BOOT_TEST_BOOT_TIMEOUT:-900}"; then
        echo "::error::no SSH after boot; see serial.log and boot-no-ssh.png"
        screenshot boot-no-ssh
        summary_line "Boot to SSH" "FAIL (see serial.log)"
        summary_files
        return 1
    fi
    summary_line "Boot to SSH" "ok after ${waited}s"
    # Passwordless sudo for the rest of the test.
    vm "sudo -S -p '' sh -c 'echo \"$user ALL=(ALL) NOPASSWD: ALL\" >/etc/sudoers.d/90-boot-test && chmod 0440 /etc/sudoers.d/90-boot-test'" \
        <"$dir/password" >/dev/null
    vm 'cat >/var/tmp/boot.sh && chmod +x /var/tmp/boot.sh' <"$here/boot.sh"

    # The greeter, once the display manager has had time to show it.
    vm 'timeout 300 bash -c "until systemctl is-active -q display-manager.service; do sleep 5; done"' || true
    sleep 20
    screenshot 01-login-screen

    echo "::group::system checks"
    set +e
    { printf '%s\n' "${GITHUB_TOKEN:-}"; } \
        | vm "read -r GITHUB_TOKEN; export GITHUB_TOKEN; EXPECTED_IMAGE='$image' /var/tmp/boot.sh system" \
        | tee "$dir/boot-system.log"
    system_rc=${PIPESTATUS[1]}
    set -e
    echo "::endgroup::"
    summary_phase "System checks" "$system_rc" "$dir/boot-system.log"

    if [[ "${BOOT_TEST_DESKTOP:-1}" == 1 ]]; then
        desktop || true
    fi
    collect_logs
    summary_files
    return "$system_rc"
}

# Reboot with autologin into Plasma (Wayland) for the test user, through a
# display manager drop-in that exists only on this VM, and screenshot it.
desktop() {
    echo "::group::desktop checks"
    local dm
    dm="$(vm 'systemctl show -P Id display-manager.service')"
    dm="${dm%.service}"
    echo "display manager: $dm"
    vm "sudo mkdir -p /etc/$dm.conf.d && printf '[Autologin]\nUser=$user\nSession=plasma.desktop\n' | sudo tee /etc/$dm.conf.d/zz-boot-test-autologin.conf"
    local boot_id
    boot_id="$(vm 'cat /proc/sys/kernel/random/boot_id')"
    vm 'sudo systemctl reboot' </dev/null || true
    local deadline=$(( SECONDS + 600 )) now=""
    until [[ "$now" =~ ^[0-9a-f-]+$ && "$now" != "$boot_id" ]]; do
        if (( SECONDS > deadline )); then
            echo "::warning::VM did not come back after reboot"
            screenshot reboot-no-ssh
            summary_line "Reboot into desktop" "FAIL: no SSH after reboot"
            desktop_rc=1
            echo "::endgroup::"
            return 1
        fi
        sleep 5
        now="$(vm 'cat /proc/sys/kernel/random/boot_id' </dev/null 2>/dev/null || true)"
    done
    summary_line "Reboot into desktop" "ok"
    set +e
    vm '/var/tmp/boot.sh desktop' </dev/null | tee "$dir/boot-desktop.log"
    desktop_rc=${PIPESTATUS[0]}
    set -e
    # Give Plasma and the cockpit a moment to settle, then once more later.
    sleep 15
    screenshot 02-desktop
    sleep 60
    screenshot 03-desktop-later
    echo "::endgroup::"
    summary_phase "Desktop checks (best effort)" "$desktop_rc" "$dir/boot-desktop.log"
}

vm() {
    ssh -i "$dir/id_ed25519" -p "$port" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=8 \
        "$user@127.0.0.1" "$@"
}

wait_ssh() {
    local start=$SECONDS
    until vm true </dev/null 2>/dev/null; do
        if (( SECONDS - start > $1 )) || ! kill -0 "$(cat "$dir/qemu.pid")" 2>/dev/null; then
            return 1
        fi
        sleep 5
    done
    waited=$(( SECONDS - start ))
}

# One QMP command to the VM's monitor.
qmp() {
    python3 - "$dir/qmp.sock" "$1" <<'EOF'
import json, socket, sys
s = socket.socket(socket.AF_UNIX)
s.connect(sys.argv[1])
f = s.makefile("rw")
json.loads(f.readline())
for cmd in ({"execute": "qmp_capabilities"}, json.loads(sys.argv[2])):
    f.write(json.dumps(cmd) + "\n")
    f.flush()
    while True:
        reply = json.loads(f.readline())
        if "event" in reply:
            continue
        if "error" in reply:
            sys.exit(reply["error"].get("desc", "QMP error"))
        break
EOF
}

screenshot() {
    local png="$dir/$1.png" ppm="$dir/$1.ppm"
    if qmp "{\"execute\": \"screendump\", \"arguments\": {\"filename\": \"$png\", \"format\": \"png\"}}" \
        && [[ -s "$png" ]]; then
        echo "screenshot $png"
    elif qmp "{\"execute\": \"screendump\", \"arguments\": {\"filename\": \"$ppm\"}}"; then
        if command -v convert >/dev/null && convert "$ppm" "$png"; then
            rm -f "$ppm"; echo "screenshot $png"
        else
            echo "screenshot $ppm"
        fi
    else
        echo "::warning::screenshot $1 failed"
    fi
}

collect_logs() {
    vm 'sudo bootc status' >"$dir/bootc-status.txt" 2>&1 || true
    # The first boot (system checks) and the autologin boot (desktop checks).
    vm 'sudo journalctl --no-pager -b -1' >"$dir/journal-boot1.log" 2>&1 || true
    vm 'sudo journalctl --no-pager -b 0' >"$dir/journal-boot2.log" 2>&1 || true
    if [[ ! -s "$dir/journal-boot1.log" || "$desktop_rc" == skipped ]]; then
        vm 'sudo journalctl --no-pager -b 0' >"$dir/journal-boot1.log" 2>&1 || true
        rm -f "$dir/journal-boot2.log"
    fi
}

cleanup() {
    if [[ -S "$dir/qmp.sock" ]]; then
        qmp '{"execute": "quit"}' 2>/dev/null || true
    fi
    sleep 2
    if [[ -e "$dir/qemu.pid" ]]; then
        kill "$(cat "$dir/qemu.pid")" 2>/dev/null || true
    fi
    rm -f "$dir/vm.qcow2" "$dir/OVMF_VARS.fd" "$dir/qemu.pid"
}

summary_init() {
    {
        echo "## AgentUX boot test"
        echo
        echo "Image: \`$1\`"
        echo
        echo "| Step | Result |"
        echo "|---|---|"
    } >"$dir/summary.md"
}

summary_line() {
    echo "| $1 | $2 |" >>"$dir/summary.md"
}

summary_phase() {
    local name="$1" rc="$2" log="$3" n_ok n_fail n_warn
    n_ok="$(grep -c '^ok ' "$log" || true)"
    n_fail="$(grep -c '^FAIL ' "$log" || true)"
    n_warn="$(grep -c '^warn ' "$log" || true)"
    summary_line "$name" "$([[ "$rc" == 0 ]] && echo ok || echo "FAIL (exit $rc)"): $n_ok ok, $n_fail failed, $n_warn warnings"
    {
        echo
        echo "<details><summary>$name</summary>"
        echo
        echo '```'
        grep -E '^(ok|FAIL|warn) |^== ' "$log" || true
        echo '```'
        echo "</details>"
        echo
    } >>"$dir/summary.extra"
}

summary_files() {
    [[ -e "$dir/summary.extra" ]] && cat "$dir/summary.extra" >>"$dir/summary.md"
    rm -f "$dir/summary.extra"
    local f names=()
    for f in "$dir"/*.png "$dir"/*.ppm "$dir"/*.log "$dir"/*.txt; do
        [[ -e "$f" ]] && names+=("$(basename "$f")")
    done
    printf '
Screenshots and logs (artifact): %s
' "${names[*]}" >>"$dir/summary.md"
}

case "${1:-}" in
    config) [[ $# == 2 ]] || { echo "usage: $0 config DIR" >&2; exit 2; }; config "$2" ;;
    run)    [[ $# == 4 ]] || { echo "usage: $0 run DISK IMAGE DIR" >&2; exit 2; }; run "$2" "$3" "$4" ;;
    *)      echo "usage: $0 config DIR | run DISK IMAGE DIR" >&2; exit 2 ;;
esac
