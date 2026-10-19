#!/usr/bin/bash
# Live ISO test checks, run as root inside the booted live system through the
# QEMU guest agent by tests/live-vm.sh (which sets LIVE_PHASE):
#
#   session   wait for the live user's graphical session (autologin)
#   checks    the live session: live boot, the selected desktop and cockpit
#             running for the live user, agentuxd answering `aux ps` with fake agents and
#             the demo runs in it, no first-login downloads; the installer
#             launcher is checked too, but only warns
#   approve   approve the demo's waiting run, so the next screenshot shows it
#             moving
#   install   install to the VM's disk (/dev/vda) with Anaconda from the live
#             system, unattended, with the live installer's own payload
#             (/usr/share/agentux/live/install.ks)
#   verify    look at the installed system on /dev/vda: its boot loader for
#             the firmware it was installed on (LIVE_FIRMWARE), its deployment tracks
#             the channel (LIVE_TRACK_IMAGE) and carries nothing from the live
#             system
#
# Prints "ok ...", "FAIL ...", "warn ..." lines (and "metric  name: value") for
# the summary; exits non-zero if a check failed.
set -uo pipefail

phase="${LIVE_PHASE:?}"
user=liveuser
image_id="${LIVE_TEST_VARIANT:-}"
if [[ -z "$image_id" && -r /usr/lib/os-release ]]; then
    # The phase checks run in the guest; installed-image verification runs on
    # the host and receives LIVE_TEST_VARIANT explicitly from live-vm.sh.
    # shellcheck source=/dev/null
    . /usr/lib/os-release
    image_id="${IMAGE_ID:-agentux}"
fi
is_cosmic=false
[[ "$image_id" == agentux-cosmic ]] && is_cosmic=true
fail=0

desktop_session_processes() {
    case "$1" in
        agentux-cosmic) printf '%s\n' cosmic-session cosmic-comp ;;
        *) printf '%s\n' kwin_wayland plasmashell ;;
    esac
}

# running USER NAME: a process of USER runs the program NAME. pgrep -x
# matches the kernel's process name, cut to 15 characters
# (lxqt-policykit-agent is "lxqt-policykit-"), so longer names are matched
# on the command line's program instead.
# shellcheck disable=SC2317,SC2329 # called through wait_for
running() {
    if (( ${#2} <= 15 )); then
        pgrep -u "$1" -x "$2" >/dev/null
    else
        pgrep -u "$1" -f "^([^ ]*/)?$2( |\$)" >/dev/null
    fi
}

ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
warn() { echo "warn $*"; }
indent() { sed 's/^/      /'; }
assert() {
    local name="$1"; shift
    local out
    if out="$("$@" 2>&1)"; then ok "$name"; else bad "$name"; indent <<<"$out"; fi
}
# wait_for SECONDS CMD...: retries CMD every 2 s until it succeeds.
wait_for() {
    local deadline=$(( SECONDS + $1 )); shift
    until "$@" >/dev/null 2>&1; do
        (( SECONDS >= deadline )) && return 1
        sleep 2
    done
}

uid() { id -u "$user"; }
# as_user CMD...: runs CMD as the live user, in their user manager's
# environment (XDG_RUNTIME_DIR, the session's PATH).
as_user() {
    runuser -u "$user" -- env XDG_RUNTIME_DIR="/run/user/$(uid)" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(uid)/bus" \
        PATH="/var/home/$user/.local/bin:/usr/local/bin:/usr/bin" "$@"
}
user_systemctl() { as_user systemctl --user "$@"; }

# The live user's graphical session. Plasma's login manager registers it as
# Type=wayland. COSMIC's greeter (greetd) starts cosmic-session from a
# session logind records as a tty one, with no Desktop, so for COSMIC the
# user's seat0 session counts once its compositor, cosmic-comp, runs.
wayland_session() {
    local id
    for id in $(loginctl list-sessions --no-legend | awk -v u="$user" '$3 == u {print $1}'); do
        if [[ "$(loginctl show-session "$id" -P Type)" == wayland ]]; then
            echo "$id"; return 0
        fi
    done
    if "$is_cosmic" && pgrep -u "$user" -x cosmic-comp >/dev/null; then
        for id in $(loginctl list-sessions --no-legend | awk -v u="$user" '$3 == u {print $1}'); do
            if [[ "$(loginctl show-session "$id" -P Seat)" == seat0 ]]; then
                echo "$id"; return 0
            fi
        done
    fi
    return 1
}

# The desktop the live user's session runs: XDG_CURRENT_DESKTOP from the
# environment of the first of their processes that has it (cosmic-comp itself
# is started before cosmic-session sets it, its clients carry it).
process_desktop() {
    local pid desktop
    for pid in $(pgrep -u "$user"); do
        desktop="$(tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null | sed -n 's/^XDG_CURRENT_DESKTOP=//p')"
        [[ -n "$desktop" ]] && { echo "$desktop"; return 0; }
    done
    return 1
}

phase_session() {
    if wait_for 600 wayland_session; then
        echo "session $(wayland_session) for $user"
        return 0
    fi
    echo "no wayland session for $user"
    loginctl list-sessions --no-legend
    systemctl --no-pager status display-manager.service livesys.service 2>&1 | tail -n 40
    return 1
}

phase_checks() {
    echo "== live boot"
    local cmdline
    cmdline="$(cat /proc/cmdline)"
    echo "      cmdline: $cmdline"
    if [[ " $cmdline " == *" rd.live.image "* ]]; then ok "booted live (rd.live.image)"; else bad "rd.live.image not on the kernel command line"; fi
    assert "live marker /usr/share/agentux/live/marker" test -e /usr/share/agentux/live/marker
    assert "root is the live overlay" bash -c 'findmnt -n -o FSTYPE / | grep -qx overlay'
    assert "livesys set up the live system" test -e /.liveimg-configured
    echo "      os-release: $(sed -n 's/^PRETTY_NAME=//p' /usr/lib/os-release)"
    echo "metric  RAM in use after login: $(free -m | awk '/^Mem:/ {print $3 " MiB of " $2 " MiB"}')"
    echo "metric  live overlay in RAM: $(df -m --output=used /run | tail -n1 | tr -d ' ') MiB used in /run"

    echo "== live session"
    local session
    if session="$(wayland_session)"; then
        ok "wayland session $session for $user ($(loginctl show-session "$session" -P Desktop))"
    else
        bad "no wayland session for $user"
    fi
    local proc
    local session_processes=()
    mapfile -t session_processes < <(desktop_session_processes "$image_id")
    if "$is_cosmic"; then
        session_processes=(cosmic-session cosmic-comp)
        local desktop
        desktop="$(loginctl show-session "$session" -P Desktop 2>/dev/null)"
        [[ -n "$desktop" ]] || desktop="$(process_desktop)"
        if [[ "${desktop,,}" == *cosmic* ]]; then
            ok "COSMIC is the active desktop session ($desktop)"
        else
            bad "active desktop is not COSMIC (${desktop:-none})"
        fi
        # COSMIC has no plasma-setup: its installs turn on Initial Setup to
        # create the account at first boot.
        if grep -qx 'firstboot --enable' /usr/share/agentux/live/install.ks; then
            ok "COSMIC installer enables Initial Setup (firstboot --enable)"
        else
            bad "COSMIC installer lacks firstboot --enable"
        fi
    fi
    for proc in "${session_processes[@]}" agentux-cockpit; do
        if wait_for 180 running "$user" "$proc"; then ok "$proc running for $user"; else bad "$proc not running for $user"; fi
    done
    if ! "$is_cosmic"; then
        local laf
        laf="$(as_user kreadconfig6 --group KDE --key LookAndFeelPackage 2>&1)"
        if [[ "$laf" == os.agentux.desktop ]]; then ok "look-and-feel is $laf"; else bad "look-and-feel is '$laf', expected os.agentux.desktop"; fi
    fi

    echo "== agentuxd with fake agents"
    assert "agentuxd.service active" user_systemctl is-active -q agentuxd.service
    local pid
    pid="$(user_systemctl show -P MainPID agentuxd.service 2>/dev/null)"
    if [[ -n "$pid" && "$pid" != 0 ]] && tr '\0' ' ' <"/proc/$pid/cmdline" | grep -q -- '--fake-agents'; then
        ok "agentuxd runs with --fake-agents  [$(tr '\0' ' ' <"/proc/$pid/cmdline")]"
    else
        bad "agentuxd does not run with --fake-agents (pid ${pid:-?})"
    fi
    if wait_for 120 test -e "/var/home/$user/.local/state/agentux/live-demo.done"; then
        ok "live demo set up (agentux-live-demo.service)"
    else
        bad "live demo not set up"
        user_systemctl status --no-pager agentux-live-demo.service 2>&1 | indent
        as_user journalctl --user --no-pager -u agentux-live-demo.service 2>&1 | tail -n 30 | indent
    fi
    local ps
    if ps="$(as_user aux ps 2>&1)"; then
        ok "aux ps answers"
        indent <<<"$ps"
        if grep -q 'WAITING FOR YOU' <<<"$ps" && grep -q 'Add a /health endpoint' <<<"$ps"; then
            ok "demo run waits for plan approval"
        else
            bad "no demo run waiting for approval in aux ps"
        fi
    else
        bad "aux ps"; indent <<<"$ps"
    fi
    if wait_for 120 bash -c "runuser -u $user -- env XDG_RUNTIME_DIR=/run/user/$(uid) aux ps --all | grep -q 'Fix the flaky login test'"; then
        ok "aux ps --all lists the approved demo run"
        as_user aux ps --all 2>&1 | indent
    else
        bad "aux ps --all does not list the approved demo run"
    fi

    echo "== no login-time downloads"
    local unit state
    for unit in agentux-first-login.service agentux-antigravity-acp.service; do
        state="$(user_systemctl show -P ActiveState "$unit" 2>&1)"
        if [[ "$state" == inactive ]]; then ok "$unit not started ($state)"; else bad "$unit is $state"; fi
        if user_systemctl is-enabled -q "$unit" 2>/dev/null; then bad "$unit enabled for the live user"; else ok "$unit not enabled"; fi
    done
    assert "no ~/.local/bin/claude (agent CLIs on demand)" test ! -e "/var/home/$user/.local/bin/claude"
    assert "Antigravity ACP server unit skips live sessions" \
        bash -c "grep -qx 'ConditionKernelCommandLine=!rd.live.image' /usr/lib/systemd/user/agentux-antigravity-acp.service.d/50-agentux-live.conf"

    echo "== installer (warnings only)"
    local desktop="/var/home/$user/Desktop"
    if [[ -e "$desktop/agentux-live-install.desktop" ]]; then ok "Install AgentUX on the desktop"; else warn "no Install AgentUX launcher on the desktop"; find "$desktop" -maxdepth 1 2>&1 | indent; fi
    # One "Install" icon on the desktop: Install AgentUX. The agent CLIs'
    # launcher (temporary, into RAM) is in the application menu only.
    local icons
    icons="$(find "$desktop" -maxdepth 1 -name '*.desktop' -printf '%f\n' 2>/dev/null | sort | paste -sd ' ')"
    if "$is_cosmic"; then
        if [[ "$icons" == "agentux-live-demo.desktop agentux-live-install.desktop" ]]; then ok "COSMIC desktop offers live demo and install icons"; else warn "COSMIC desktop icons: '$icons'"; fi
    elif [[ "$icons" == agentux-live-install.desktop ]]; then ok "Install AgentUX is the only desktop icon"; else warn "desktop icons: '$icons', expected only agentux-live-install.desktop"; fi
    local clis=/usr/share/applications/agentux-live-agent-clis.desktop
    if grep -qx 'Name=Try the agent CLIs in this session' "$clis" && grep -q '^Comment=.*(RAM).*reboot' "$clis"; then
        ok "\"Try the agent CLIs in this session\" in the application menu (says RAM, gone on reboot)"
    else
        warn "the agent CLIs' menu launcher is not \"Try the agent CLIs in this session\" with its RAM note"; indent <"$clis"
    fi
    if [[ ! -e "$desktop/liveinst.desktop" ]]; then ok "Fedora's installer launcher replaced"; else warn "Fedora's liveinst.desktop is still on the desktop"; fi
    if ! "$is_cosmic"; then
        if grep -q 'agentux-live-install.desktop' "/var/home/$user/.config/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null; then
            ok "Install AgentUX pinned in the panel"
        else
            warn "Install AgentUX not in the panel's launchers"
        fi
    fi
    if command -v liveinst >/dev/null && command -v anaconda >/dev/null; then ok "liveinst and anaconda installed"; else warn "liveinst or anaconda missing"; fi
    if grep -q '^%include /usr/share/agentux/live/install.ks' /usr/share/anaconda/interactive-defaults.ks \
        && grep -q "^ostreecontainer --url=$(cat /usr/share/agentux/live/install-image) --transport=registry$" /usr/share/agentux/live/install.ks; then
        ok "installer payload: $(cat /usr/share/agentux/live/install-image) from the registry, then following $(cat /usr/share/agentux/live/track-image)"
    else
        warn "installer payload not configured"; indent </usr/share/agentux/live/install.ks
    fi
    local branding
    # shellcheck source=/dev/null
    branding="/usr/share/cockpit/branding/$(. /etc/os-release && echo "$ID-$VARIANT_ID")"
    if [[ -f $branding/branding.css && -f $branding/logo.png ]] && grep -q '#c6f36b' "$branding/branding.css"; then
        ok "installer branding: $branding (05-installer.png shows it)"
    else
        warn "no AgentUX installer branding in $branding"
    fi

    echo "== failed units"
    local failed
    failed="$(systemctl --failed --no-legend --plain 2>&1)"
    if [[ -z "$failed" ]]; then ok "no failed system units"; else warn "failed system units:"; indent <<<"$failed"; fi
    failed="$(user_systemctl --failed --no-legend --plain 2>&1)"
    if [[ -z "$failed" ]]; then ok "no failed user units"; else warn "failed user units:"; indent <<<"$failed"; fi
}

phase_approve() {
    local request
    request="$(as_user aux ps | awk '$2 == "run" { print $1; exit }')"
    if [[ -n "$request" ]] && as_user aux approve "$request" --message "approved by the live test"; then
        ok "approved demo request $request"
    else
        warn "could not approve the demo run"
    fi
}

# The disk the install goes to: the VM's only disk.
# LIVE_TARGET: the installed disk as the host sees it, for verify run there.
target="${LIVE_TARGET:-/dev/vda}"

phase_install() {
    test -b "$target" || { bad "no $target to install to"; return; }
    # In live mode (liveinst, --liveinst) Anaconda takes no kickstart: its
    # interactive defaults are only defaults, and the disk must be picked in
    # the UI. So the test runs Anaconda as a plain kickstart install from the
    # live system instead, with the answers below and the live installer's
    # own payload (install.ks: the registry pull and the bootc switch).
    cat >/var/tmp/install-test.ks <<EOF
# Live ISO test install: the answers the installer UI would get, and the
# payload the live installer uses.
cmdline
lang en_US.UTF-8
keyboard us
timezone UTC --utc
ignoredisk --only-use=${target#/dev/}
zerombr
clearpart --all --initlabel --drives=${target#/dev/}
autopart --noswap
rootpw --lock
# A graphical boot, as an install from the web UI gives (text mode would
# default to multi-user.target).
xconfig --startxonboot
user --name=installtest --password=installtest --plaintext --groups=wheel
%include /usr/share/agentux/live/install.ks
EOF
    echo "      kickstart:"; indent </var/tmp/install-test.ks
    # The install takes a while and fills RAM (the live root and /var/tmp
    # are tmpfs), so it runs as a unit of its own and install-result reports
    # on it; the guest agent is kept out of the OOM killer's way.
    local pid
    for pid in $(pidof qemu-ga); do echo -1000 >"/proc/$pid/oom_score_adj"; done
    # In /run: Anaconda remounts /var/tmp during the install.
    rm -rf /run/agentux-install-test && mkdir -p /run/agentux-install-test
    date +%s >/run/agentux-install-test/start
    # Anaconda wants a session bus of its own.
    systemd-run --unit=agentux-install-test --collect --property=OOMScoreAdjust=500 \
        bash -c 'dbus-run-session -- anaconda --cmdline --kickstart /var/tmp/install-test.ks >/run/agentux-install-test/anaconda.out 2>&1; echo $? >/run/agentux-install-test/rc'
    ok "install started (agentux-install-test.service)"
}

# Prints a line while the install runs; exits 0 once it has finished.
phase_install_done() {
    if [[ -e /run/agentux-install-test/rc ]]; then return 0; fi
    echo "installing: $(free -m | awk '/^Mem:/ {print $3 "/" $2 " MiB"}'), /var/tmp $(df -m --output=used /var/tmp | tail -n1 | tr -d ' ') MiB, $(tail -n1 /run/agentux-install-test/anaconda.out 2>/dev/null | cut -c1-120)"
    systemctl is-active -q agentux-install-test.service || { echo "install unit gone without a result"; return 0; }
    return 1
}

phase_install_result() {
    local rc
    rc="$(cat /run/agentux-install-test/rc 2>/dev/null || echo "none")"
    echo "metric  RAM after the install: $(free -m | awk '/^Mem:/ {print $3 " MiB of " $2 " MiB"}')"
    if journalctl -k --no-pager | grep -qi 'out of memory'; then
        echo "      the kernel killed processes for lack of memory:"
        journalctl -k --no-pager | grep -i 'out of memory\|killed process' | tail -n 10 | indent
    fi
    # Anaconda halts the system at the end of a kickstart install (the
    # default), often before its unit can write the result: then the
    # installed disk, checked from the host, decides.
    if [[ "$rc" == none ]]; then
        echo "      no exit status: Anaconda is halting the live system after the install; the installed disk decides"
        tail -n 40 /run/agentux-install-test/anaconda.out 2>/dev/null | indent
        return
    fi
    # Anaconda can exit 0 without installing; the disk tells.
    if [[ "$rc" == 0 ]] && ! lsblk -lnpo FSTYPE "$target" | grep -qE 'btrfs|xfs|ext4'; then
        echo "      no file system on $target after the install"
        rc=1
    fi
    tail -n 40 /run/agentux-install-test/anaconda.out | indent
    if [[ "$rc" == 0 ]] && ! grep -qi 'traceback\|installation failed' /run/agentux-install-test/anaconda.out; then
        ok "anaconda installed to $target"
    else
        bad "anaconda failed (exit $rc)"
        tail -n 80 /tmp/anaconda.log 2>/dev/null | indent
        tail -n 80 /tmp/packaging.log 2>/dev/null | indent
        grep -E " (ERR|WRN) " /tmp/storage.log 2>/dev/null | tail -n 40 | indent
    fi
}

phase_verify() {
    local mnt=/var/tmp/installed part=""
    mkdir -p "$mnt"
    umount -R "$mnt" 2>/dev/null
    # The partition holding the ostree repository (Btrfs, Kinoite's layout).
    for part in $(lsblk -lnpo NAME,FSTYPE "$target" | awk '$2 == "btrfs" || $2 == "xfs" || $2 == "ext4" {print $1}'); do
        if mount -o ro "$part" "$mnt" 2>/dev/null || mount -o ro,rescue=nologreplay "$part" "$mnt" 2>/dev/null; then
            [[ -n "$(find "$mnt" -maxdepth 4 -path '*/ostree/deploy' -print -quit 2>/dev/null)" ]] && break
            umount "$mnt"
        fi
        part=""
    done
    if [[ -z "$part" ]]; then bad "no ostree deployment on $target"; lsblk -f "$target" | indent; return; fi
    local origin deploy image
    origin="$(find "$mnt" -maxdepth 7 -path '*/ostree/deploy/*/deploy/*.origin' -print -quit)"
    deploy="${origin%.origin}"
    image="${LIVE_TRACK_IMAGE:-$(cat /usr/share/agentux/live/track-image 2>/dev/null)}"
    echo "      deployment: ${deploy#"$mnt"}"
    indent <"$origin"
    if grep -qx "container-image-reference=ostree-unverified-registry:$image" "$origin"; then
        ok "installed system tracks $image from the registry (as a bootc-image-builder install does)"
    else
        bad "installed system's origin does not track $image"
    fi
    if [[ -e "$deploy/usr/share/agentux/live" ]]; then bad "live-only /usr/share/agentux/live in the installed system"; else ok "no live-only files in /usr"; fi
    if [[ "$image" == ghcr.io/agentux-os/agentux-cosmic:* || "$image" == ghcr.io/agentux-os/agentux-cosmic@sha256:* ]]; then
        if [[ -f "$deploy/usr/share/wayland-sessions/cosmic.desktop" && -x "$deploy/usr/libexec/initial-setup/run-gui-backend" ]]; then
            ok "installed COSMIC session and Initial Setup backend"
        else
            bad "installed COSMIC session or Initial Setup backend missing"
        fi
    fi
    if grep -q '^liveuser:' "$deploy/etc/passwd" 2>/dev/null; then bad "liveuser exists in the installed system"; else ok "no liveuser in the installed system"; fi
    if grep -q '^installtest:' "$deploy/etc/passwd" 2>/dev/null; then ok "the installer's user exists"; else warn "installtest user not found in the deployment's /etc/passwd"; fi
    if [[ -L "$deploy/etc/systemd/user/default.target.wants/agentux-first-login.service" \
        && -L "$deploy/etc/systemd/user/default.target.wants/agentux-antigravity-acp.service" \
        && ! -L "$deploy/etc/systemd/user/default.target.wants/agentux-live-demo.service" ]]; then
        ok "installed system runs first-login and the ACP server unit, not the live demo"
    else
        bad "installed system's user units differ from the image's"
    fi
    if [[ ! -e "$deploy/usr/lib/systemd/user/agentuxd.service.d/50-agentux-live.conf" ]]; then
        ok "agentuxd without the live fake-agents override"
    else
        bad "live agentuxd override in the installed system"
    fi
    # No root entry in fstab: systemd-remount-fs would fail on the composefs
    # root at every boot (install.ks comments it out).
    if [[ -f "$deploy/etc/fstab" ]] && ! awk '$2 == "/" && $1 !~ /^#/ {found = 1} END {exit !found}' "$deploy/etc/fstab"; then
        ok "no root entry in /etc/fstab (ostree mounts /)"
    else
        bad "/etc/fstab mounts / (systemd-remount-fs would fail)"
        indent <"$deploy/etc/fstab" 2>/dev/null
    fi
    # The boot loader for the firmware the install ran on (LIVE_FIRMWARE, set
    # by live-vm.sh): on BIOS, Anaconda's autopart adds a BIOS boot partition
    # to the GPT and bootupd puts GRUB's i386-pc core there and its boot code
    # in the MBR; on UEFI, an EFI system partition with shim.
    local parts
    parts="$(sfdisk --dump "$target" 2>&1)"
    case "${LIVE_FIRMWARE:-}" in
        bios)
            if grep -qi '21686148-6449-6e6f-744e-656564454649' <<<"$parts"; then
                ok "BIOS boot partition on $target"
            else
                bad "no BIOS boot partition on $target"; indent <<<"$parts"
            fi
            if head -c 440 "$target" | grep -aq GRUB; then
                ok "GRUB's boot code in $target's MBR (bootupd's BIOS install)"
            else
                bad "no GRUB boot code in $target's MBR"
            fi
            ;;
        uefi)
            if grep -qi 'c12a7328-f81f-11d2-ba4b-00a0c93ec93b' <<<"$parts"; then
                ok "EFI system partition on $target"
            else
                bad "no EFI system partition on $target"; indent <<<"$parts"
            fi
            ;;
    esac
    if jq -e '.transports.docker["ghcr.io/agentux-os/agentux"][0].type == "sigstoreSigned"' "$deploy/etc/containers/policy.json" >/dev/null 2>&1; then
        ok "signature policy requires the AgentUX key"
    else
        bad "installed policy.json lacks the AgentUX signature requirement"
    fi
    umount "$mnt"
}

case "$phase" in
    desktop-processes) desktop_session_processes "$image_id"; exit $? ;;
    session) phase_session; exit $? ;;
    checks) phase_checks ;;
    approve) phase_approve ;;
    install) phase_install ;;
    install-done) phase_install_done; exit $? ;;
    install-result) phase_install_result ;;
    verify) phase_verify ;;
    *) echo "unknown phase $phase" >&2; exit 2 ;;
esac
exit "$fail"
