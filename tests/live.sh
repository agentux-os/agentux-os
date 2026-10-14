#!/usr/bin/bash
# Live ISO test checks, run as root inside the booted live system through the
# QEMU guest agent by tests/live-vm.sh (which sets LIVE_PHASE):
#
#   session   wait for the live user's graphical session (autologin)
#   checks    the live session: live boot, Plasma and the cockpit running for
#             the live user, agentuxd answering `aux ps` with fake agents and
#             the demo runs in it, no first-login downloads; the installer
#             launcher is checked too, but only warns
#   approve   approve the demo's waiting run, so the next screenshot shows it
#             moving
#   install   install to the VM's disk (/dev/vda) with Anaconda from the live
#             system, unattended, with the live installer's own payload
#             (/usr/share/agentux/live/install.ks)
#   verify    look at the installed system on /dev/vda: its deployment tracks
#             the published image and carries nothing from the live system
#
# Prints "ok ...", "FAIL ...", "warn ..." lines (and "metric  name: value") for
# the summary; exits non-zero if a check failed.
set -uo pipefail

phase="${LIVE_PHASE:?}"
user=liveuser
fail=0

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

wayland_session() {
    local id
    for id in $(loginctl list-sessions --no-legend | awk -v u="$user" '$3 == u {print $1}'); do
        if [[ "$(loginctl show-session "$id" -P Type)" == wayland ]]; then
            echo "$id"; return 0
        fi
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
    for proc in kwin_wayland plasmashell agentux-cockpit; do
        if wait_for 180 pgrep -u "$user" -x "$proc"; then ok "$proc running for $user"; else bad "$proc not running for $user"; fi
    done
    local laf
    laf="$(as_user kreadconfig6 --group KDE --key LookAndFeelPackage 2>&1)"
    if [[ "$laf" == os.agentux.desktop ]]; then ok "look-and-feel is $laf"; else bad "look-and-feel is '$laf', expected os.agentux.desktop"; fi

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
    if [[ -e "$desktop/agentux-live-agent-clis.desktop" ]]; then ok "Install the agent CLIs on the desktop"; else warn "no agent CLIs launcher on the desktop"; fi
    if [[ ! -e "$desktop/liveinst.desktop" ]]; then ok "Fedora's installer launcher replaced"; else warn "Fedora's liveinst.desktop is still on the desktop"; fi
    if grep -q 'agentux-live-install.desktop' "/var/home/$user/.config/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null; then
        ok "Install AgentUX pinned in the panel"
    else
        warn "Install AgentUX not in the panel's launchers"
    fi
    if command -v liveinst >/dev/null && command -v anaconda >/dev/null; then ok "liveinst and anaconda installed"; else warn "liveinst or anaconda missing"; fi
    if grep -q '^%include /usr/share/agentux/live/install.ks' /usr/share/anaconda/interactive-defaults.ks \
        && grep -q "^ostreecontainer --url=$(cat /usr/share/agentux/live/install-image) --transport=registry$" /usr/share/agentux/live/install.ks; then
        ok "installer payload: $(cat /usr/share/agentux/live/install-image) from the registry"
    else
        warn "installer payload not configured"; indent </usr/share/agentux/live/install.ks
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
    image="${LIVE_INSTALL_IMAGE:-$(cat /usr/share/agentux/live/install-image 2>/dev/null)}"
    echo "      deployment: ${deploy#"$mnt"}"
    indent <"$origin"
    if grep -qx "container-image-reference=ostree-unverified-registry:$image" "$origin"; then
        ok "installed system tracks $image from the registry (as a bootc-image-builder install does)"
    else
        bad "installed system's origin does not track $image"
    fi
    if [[ -e "$deploy/usr/share/agentux/live" ]]; then bad "live-only /usr/share/agentux/live in the installed system"; else ok "no live-only files in /usr"; fi
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
    if jq -e '.transports.docker["ghcr.io/agentux-os/agentux"][0].type == "sigstoreSigned"' "$deploy/etc/containers/policy.json" >/dev/null 2>&1; then
        ok "signature policy requires the AgentUX key"
    else
        bad "installed policy.json lacks the AgentUX signature requirement"
    fi
    umount "$mnt"
}

case "$phase" in
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
