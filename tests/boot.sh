#!/usr/bin/bash
# Boot test checks, run inside a booted AgentUX VM as the test user (over SSH,
# with passwordless sudo) by tests/boot-vm.sh:
#   boot.sh system   the booted image, system and user units, the boot
#                    splash (theme, initramfs, rhgb), the first-boot
#                    wizard's session, first login, agentuxd, an end-to-end
#                    run with fake agents and one with checks in rootless
#                    Podman (that one only warns)
#   boot.sh desktop  after an autologin reboot: the Plasma session, the
#                    cockpit and no Welcome Center (reported, but boot-vm.sh
#                    does not fail on them)
#   boot.sh sample UNIT MARKER
#                    samples a unit's memory (first-login's, the Antigravity
#                    ACP server's) until it completed (run in the background
#                    from the first SSH login)
# EXPECTED_IMAGE is the image reference the system should have booted, and
# EXPECTED_AUX_VERSION the agentux-core version `aux --version` should report. An
# optional GITHUB_TOKEN is used only to retry a failed first login (mise
# resolves versions through the GitHub API, which CI runners share).
set -uo pipefail

phase="${1:?usage: boot.sh system|desktop|sample}"
fail=0
ok()   { printf 'ok    %s\n' "$*"; }
bad()  { printf 'FAIL  %s\n' "$*"; fail=1; }
warn() { printf 'warn  %s\n' "$*"; }
# A measurement for the job summary: a name and a value.
metric() { printf 'metric  %s: %s\n' "$1" "$2"; }
indent() { sed 's/^/      /'; }

# A description and a command that must succeed; its first output line is shown.
assert() {
    local what="$1"; shift
    local out
    if out="$("$@" 2>&1 </dev/null)"; then
        ok "$what${out:+  [$(head -n1 <<<"$out")]}"
    else
        bad "$what"
        indent <<<"$out"
    fi
}

# Polls a command until it succeeds or `timeout` seconds pass.
wait_for() {
    local timeout="$1"; shift
    local deadline=$(( SECONDS + timeout ))
    until "$@" >/dev/null 2>&1 </dev/null; do
        (( SECONDS >= deadline )) && return 1
        sleep 5
    done
}

uid="$(id -u)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$uid}"
state="${XDG_STATE_HOME:-$HOME/.local/state}/agentux"
marker="$state/first-login.done"
acp_unit=agentux-antigravity-acp.service
acp_marker="$state/antigravity-acp.done"
memory_samples=/var/tmp/first-login-memory

failed_units() {
    # $1: --system or --user
    local units unit
    units="$(systemctl "$1" --failed --plain --no-legend 2>&1 | awk '{print $1}')"
    if [[ -z "$units" ]]; then
        ok "systemctl $1 --failed is empty"
        return
    fi
    for unit in $units; do
        # Antigravity's ACP server is optional; check_antigravity_acp reports it.
        if [[ "$unit" == "$acp_unit" ]]; then
            warn "failed unit ($1): $unit (optional)"
            continue
        fi
        bad "failed unit ($1): $unit"
        systemctl "$1" status --no-pager --lines=15 "$unit" 2>&1 | indent
    done
}

check_image() {
    echo "== booted image"
    local status booted
    status="$(sudo bootc status --format=json 2>&1)" || { bad "bootc status"; indent <<<"$status"; return; }
    booted="$(jq -r '.status.booted.image.image.image // empty' <<<"$status")"
    echo "      booted: $booted"
    echo "      digest: $(jq -r '.status.booted.image.imageDigest // "?"' <<<"$status")"
    echo "      version: $(jq -r '.status.booted.image.version // "?"' <<<"$status")"
    if [[ -n "$booted" && "$booted" == "${EXPECTED_IMAGE:-}" ]]; then
        ok "bootc booted $booted"
    else
        bad "bootc booted '${booted:-nothing}', expected '${EXPECTED_IMAGE:-?}'"
    fi
}

# The AgentUX boot splash: selected, in the initramfs the system booted with
# (built into the image, /usr/lib/modules/$kver/initramfs.img), and asked for
# on the kernel command line (rhgb, from the image's bootc kargs.d). Whether
# it showed on screen is boot-vm.sh's to report, from its screendumps.
check_splash() {
    echo "== boot splash"
    local theme initramfs list
    theme="$(plymouth-set-default-theme 2>&1)"
    if [[ "$theme" == agentux ]]; then
        ok "plymouth-set-default-theme: agentux"
    else
        bad "plymouth-set-default-theme: '$theme', expected agentux"
    fi
    initramfs="/usr/lib/modules/$(uname -r)/initramfs.img"
    if ! list="$(sudo lsinitrd "$initramfs" 2>/dev/null)" || [[ -z "$list" ]]; then
        bad "lsinitrd $initramfs"
        return
    fi
    if grep -q 'usr/share/plymouth/themes/agentux/agentux.script$' <<<"$list"; then
        ok "initramfs has plymouth/themes/agentux  [$(grep -c 'plymouth/themes/agentux/' <<<"$list") files]"
    else
        bad "initramfs has no plymouth/themes/agentux"
        grep 'plymouth/themes/' <<<"$list" | indent
    fi
    if grep -q '/plymouth/script.so$' <<<"$list"; then
        ok "initramfs has Plymouth's script plugin"
    else
        bad "initramfs has no Plymouth script plugin (script.so)"
    fi
    if grep -qw rhgb /proc/cmdline; then
        ok "kernel command line has rhgb"
    else
        bad "kernel command line has no rhgb: $(cat /proc/cmdline)"
    fi
}

check_system() {
    echo "== system units"
    local state
    state="$(timeout 300 systemctl is-system-running --wait 2>&1)"
    echo "      system state: $state"
    failed_units --system
    assert "display manager active" systemctl is-active display-manager.service
}

# Polls a oneshot user unit until it finished (its marker exists), failed for
# good, failed once and waits to restart, or `limit` seconds passed. Sets st
# and sub.
watch_unit() {
    local unit="$1" done_marker="$2" limit="$3" start=$SECONDS
    while true; do
        st="$(systemctl --user show -P ActiveState "$unit")"
        sub="$(systemctl --user show -P SubState "$unit")"
        [[ "$st" == inactive && -e "$done_marker" ]] && return
        [[ "$st" == failed || "$sub" == auto-restart ]] && return
        (( SECONDS - start >= limit )) && return
        sleep 5
    done
}

# A unit's TimeoutStartSec in seconds, or nothing if it has none.
start_timeout() {
    local v us
    v="$(systemctl --user show -P TimeoutStartUSec "$1")"
    [[ -z "$v" || "$v" == infinity ]] && return
    us="$(systemd-analyze timespan "$v" 2>/dev/null | awk 'NR == 2 {print $2}')"
    [[ "$us" =~ ^[0-9]+$ ]] && echo $(( us / 1000000 ))
}

# How long the unit's last run of ExecStart took, in seconds.
run_seconds() {
    local start exit
    start="$(systemctl --user show -P ExecMainStartTimestampMonotonic "$1")"
    exit="$(systemctl --user show -P ExecMainExitTimestampMonotonic "$1")"
    if [[ "$start" =~ ^[1-9][0-9]*$ && "$exit" =~ ^[1-9][0-9]*$ ]] && (( exit >= start )); then
        echo $(( (exit - start) / 1000000 ))
    fi
}

# Checks that a unit ($1) has a start timeout and that its last run finished
# within it ($4 says how to report a run over it: bad or warn), and reports
# the run's and each step's result and duration (from first-login's steps
# file $2) as metrics named after $3.
report_timings() {
    local unit="$1" steps="$2" label="$3" over="$4" budget took
    budget="$(start_timeout "$unit")"
    if [[ -n "$budget" ]]; then
        ok "$unit has TimeoutStartSec=${budget}s"
    else
        bad "$unit has no TimeoutStartSec (a oneshot unit then waits forever)"
    fi
    took="$(run_seconds "$unit")"
    if [[ -n "$took" && -n "$budget" ]]; then
        if (( took <= budget )); then
            ok "$unit's last run took ${took}s, within its ${budget}s"
        else
            "$over" "$unit's last run took ${took}s, over its ${budget}s"
        fi
    fi
    metric "$label wall clock" "${took:-?}s (TimeoutStartSec ${budget:-none}s, $(systemctl --user show -P NRestarts "$unit") restarts)"
    local name result secs step_budget
    if [[ -r "$steps" ]]; then
        while IFS=$'\t' read -r name result secs step_budget; do
            metric "$label: $name" "$result in ${secs}s (budget ${step_budget}s)"
        done <"$steps"
    else
        warn "no step timings in $steps"
    fi
}

# What systemd logged the unit's last run used (CPU time, memory peak).
report_used() {
    local used
    used="$(journalctl --user -u "$1" --no-pager -o cat \
        | sed -n 's/^.*: Consumed //p' | tail -n1)"
    echo "      used: ${used:-?}"
    metric "$2 run" "${used:-?}"
}

# Started by boot-vm.sh as transient user services right after the first SSH
# login, which starts the user manager and with it first-login: samples the
# cgroup of a unit ($1, done once marker $2 exists) every second until it
# completed, for what systemd's own "memory peak" does not tell apart. Writes
# to $memory_samples.<unit>: the largest anonymous memory seen in bytes (what
# MemoryHigh cannot reclaim without swap), the largest count of reclaims for
# going over MemoryHigh, and the number of samples.
sample_memory() {
    local unit="$1" done_marker="$2" out="$memory_samples.$1" deadline=$(( SECONDS + 7200 ))
    local cg anon high anon_max=0 high_max=0 samples=0
    while (( SECONDS < deadline )); do
        cg="/sys/fs/cgroup$(systemctl --user show -P ControlGroup "$unit")"
        if [[ "$cg" != /sys/fs/cgroup && -r "$cg/memory.stat" ]]; then
            anon="$(awk '$1 == "anon" {print $2}' "$cg/memory.stat")"
            high="$(awk '$1 == "high" {print $2}' "$cg/memory.events")"
            (( ${anon:-0} > anon_max )) && anon_max="$anon"
            (( ${high:-0} > high_max )) && high_max="$high"
            samples=$(( samples + 1 ))
            echo "$anon_max $high_max $samples" >"$out.tmp"
            mv "$out.tmp" "$out"
        elif [[ -e "$done_marker" ]]; then
            return 0
        fi
        sleep 1
    done
}

# The memory samples of a unit ($1) as a metric named after $2; $3 is the
# sampler's unit.
report_memory() {
    local unit="$1" label="$2" sampler="$3" anon_max high_max samples
    wait_for 30 bash -c "! systemctl --user is-active -q $sampler"
    if read -r anon_max high_max samples 2>/dev/null <"$memory_samples.$unit"; then
        metric "$label largest anonymous memory" \
            "$(( anon_max / 1048576 ))M (sampled each second, $samples samples); MemoryHigh=$(systemctl --user show -P MemoryHigh "$unit"), reclaimed for going over it $high_max times"
    else
        warn "no memory samples of $unit in $memory_samples.$unit"
    fi
}

# The user manager: linger, failed units and the first-login service.
check_first_login() {
    echo "== user session and first login"
    assert "enable-linger $USER" sudo loginctl enable-linger "$USER"
    wait_for 120 systemctl --user is-active default.target \
        || warn "user default.target not active after 2 minutes"

    local unit=agentux-first-login.service
    assert "nm-online (first-login waits for the network with it)" test -x /usr/bin/nm-online
    assert "$unit restarts on failure" \
        bash -c "systemctl --user show -P Restart $unit | grep -qx on-failure"
    # systemd bounds each run by TimeoutStartSec; a little longer covers the
    # wait for the network before it.
    local budget limit st="" sub=""
    budget="$(start_timeout "$unit")"
    limit="${FIRST_LOGIN_TIMEOUT:-$(( ${budget:-1800} + 120 ))}"
    echo "      waiting up to ${limit}s for $unit"
    watch_unit "$unit" "$marker" "$limit"
    echo "      $unit: $st/$sub, result $(systemctl --user show -P Result "$unit"), restarts $(systemctl --user show -P NRestarts "$unit"), ran $(systemctl --user show -P ExecMainStartTimestamp "$unit") .. $(systemctl --user show -P ExecMainExitTimestamp "$unit")"
    if [[ ! -e "$marker" && -n "${GITHUB_TOKEN:-}" ]]; then
        warn "first login did not complete on its own; its log:"
        journalctl --user -u "$unit" --no-pager -o cat -n 40 | indent
        echo "      retrying now with GITHUB_TOKEN in the user manager environment"
        systemctl --user set-environment GITHUB_TOKEN="$GITHUB_TOKEN"
        systemctl --user reset-failed "$unit"
        systemctl --user start --no-block "$unit"
        sleep 5
        watch_unit "$unit" "$marker" "$limit"
        systemctl --user unset-environment GITHUB_TOKEN
    fi
    if [[ -e "$marker" ]]; then
        ok "$unit completed (marker $marker)"
    else
        bad "$unit did not complete"
        journalctl --user -u "$unit" --no-pager -o cat -n 60 | indent
    fi
    # The run that completed is the last one; systemd logs what it used when
    # it stops.
    report_timings "$unit" "$state/first-login.steps" first-login bad
    report_used "$unit" first-login
    report_memory "$unit" first-login boot-test-memory.service
}

# Antigravity's ACP server, in a lower-priority unit of its own that runs
# after first-login. It is optional: only a missing start timeout fails here.
check_antigravity_acp() {
    echo "== Antigravity ACP server (optional, own unit)"
    local unit="$acp_unit" budget limit st="" sub=""
    assert "$unit runs at low priority (Nice=19, IOSchedulingClass=idle)" \
        bash -c "systemctl --user show -P Nice $unit | grep -qx 19 && systemctl --user show -P IOSchedulingClass $unit | grep -qxE '3|idle'"
    budget="$(start_timeout "$unit")"
    limit="${ACP_TIMEOUT:-$(( ${budget:-1500} + 120 ))}"
    echo "      waiting up to ${limit}s for $unit"
    watch_unit "$unit" "$acp_marker" "$limit"
    echo "      $unit: $st/$sub, result $(systemctl --user show -P Result "$unit"), restarts $(systemctl --user show -P NRestarts "$unit"), ran $(systemctl --user show -P ExecMainStartTimestamp "$unit") .. $(systemctl --user show -P ExecMainExitTimestamp "$unit")"
    if [[ -e "$acp_marker" ]]; then
        ok "$unit completed (marker $acp_marker)"
    else
        warn "$unit did not complete (optional); its log:"
        journalctl --user -u "$unit" --no-pager -o cat -n 40 | indent
    fi
    local fl_exit acp_start
    fl_exit="$(systemctl --user show -P ExecMainExitTimestampMonotonic agentux-first-login.service)"
    acp_start="$(systemctl --user show -P ExecMainStartTimestampMonotonic "$unit")"
    if [[ "$fl_exit" =~ ^[1-9][0-9]*$ && "$acp_start" =~ ^[1-9][0-9]*$ ]]; then
        if (( acp_start >= fl_exit )); then
            ok "$unit started after first-login finished"
        else
            warn "$unit started before first-login finished"
        fi
    fi
    report_timings "$unit" "$state/antigravity-acp.steps" "Antigravity ACP server" warn
    report_used "$unit" "Antigravity ACP server"
    report_memory "$unit" "Antigravity ACP server" boot-test-memory-acp.service
    failed_units --user
}

# The units are enabled globally, so every user manager gets them, including
# those of system users with a session (plasma-setup's first-boot wizard).
# Their messages in the journal carry the manager's UID.
check_system_users() {
    echo "== AgentUX user units only run for regular users"
    local uid_min unit uids u
    uid_min="$(awk '$1 == "UID_MIN" {print $2}' /etc/login.defs)"
    # The cockpit's autostart unit starts for every graphical session and its
    # wrapper exits for system users; check_wizard_session covers it.
    for unit in agentux-first-login.service "$acp_unit" agentuxd.service; do
        # Only "Starting/Started" count; a manager whose condition check
        # skipped the unit logs that under USER_UNIT too.
        uids="$(sudo journalctl -b -o json USER_UNIT="$unit" \
            | jq -r 'select((.MESSAGE | type) == "string" and (.MESSAGE | startswith("Start"))) | ._UID' \
            | sort -un | tr '\n' ' ')"
        uids="${uids% }"
        local system_uids=()
        for u in $uids; do
            (( u < ${uid_min:-1000} )) && system_uids+=("$u ($(id -nu "$u" 2>/dev/null))")
        done
        if (( ${#system_uids[@]} == 0 )); then
            ok "$unit ran only for UIDs >= ${uid_min:-1000} [${uids:-none}]"
        else
            bad "$unit also ran for system users: ${system_uids[*]}"
        fi
    done
}

# The first-boot wizard runs a full Plasma session as the system user
# plasma-setup (UID 968), still logged in while these checks run. Its XDG
# autostart starts the cockpit's unit there too; agentux-desktop's wrapper
# (/usr/libexec/agentux-cockpit-autostart) logs that it skips system users and
# exits 0, so nothing of AgentUX runs over the wizard.
check_wizard_session() {
    echo "== first-boot wizard session (system user plasma-setup)"
    local wuid manager unit='app-agentux\x2dcockpit@autostart.service' out proc
    wuid="$(id -u plasma-setup 2>/dev/null)"
    if [[ -z "$wuid" ]] || ! loginctl show-user "$wuid" >/dev/null 2>&1; then
        bad "no session of plasma-setup (the first-boot wizard) on this boot"
        loginctl list-sessions --no-legend | indent
        return
    fi
    echo "      plasma-setup is UID $wuid"
    manager=(sudo systemctl --user --machine=plasma-setup@)

    # The wrapper's own line (the unit's stderr) and the user manager's
    # messages about the unit.
    out="$(sudo journalctl -b --no-pager -o cat _UID="$wuid" _SYSTEMD_USER_UNIT="$unit" \
        + _UID="$wuid" USER_UNIT="$unit" 2>&1)"
    if grep -q 'agentux-cockpit: not starting for system user' <<<"$out"; then
        ok "$unit logged \"agentux-cockpit: not starting for system user\" for UID $wuid  [$(grep -m1 'not starting' <<<"$out")]"
    else
        bad "$unit did not log \"agentux-cockpit: not starting for system user\" for UID $wuid"
        indent <<<"$out"
    fi
    local props
    props="$("${manager[@]}" show -p Result -p ExecMainStatus -p ActiveState -p ExecMainExitTimestamp "$unit" 2>&1)"
    if grep -qx 'Result=success' <<<"$props" && grep -qx 'ExecMainStatus=0' <<<"$props" \
        && grep -q '^ExecMainExitTimestamp=.\+' <<<"$props"; then
        ok "$unit exited successfully for UID $wuid  [$(tr '\n' ' ' <<<"$props")]"
    elif grep -q 'Deactivated successfully' <<<"$out" && ! grep -q 'Failed with result' <<<"$out"; then
        ok "$unit exited successfully for UID $wuid (journal)"
    else
        bad "$unit did not exit successfully for UID $wuid"
        indent <<<"$props"
    fi

    out="$("${manager[@]}" --failed --plain --no-legend 2>&1)"
    if [[ $? -eq 0 && -z "$out" ]]; then
        ok "no failed unit in plasma-setup's user manager"
    else
        bad "failed units in plasma-setup's user manager (or it could not be asked)"
        indent <<<"$out"
    fi

    for proc in agentux-cockpit agentuxd; do
        if out="$(pgrep -a -u "$wuid" -x "$proc")"; then
            bad "$proc runs as UID $wuid"; indent <<<"$out"
        else
            ok "$proc not running as UID $wuid"
        fi
    done
    if out="$(pgrep -a -u "$wuid" -f /usr/libexec/agentux/first-login)"; then
        bad "first-login runs as UID $wuid"; indent <<<"$out"
    else
        ok "first-login not running as UID $wuid"
    fi
    for unit in agentuxd.service agentux-first-login.service "$acp_unit"; do
        out="$("${manager[@]}" is-active "$unit" 2>&1)"
        if [[ "$out" == active || "$out" == activating ]]; then
            bad "$unit is $out in plasma-setup's user manager"
        else
            ok "$unit not active in plasma-setup's user manager  [$out]"
        fi
    done
}

# agentux-desktop's Plasma overlay: the login screen's AgentUX defaults.
check_desktop_files() {
    echo "== AgentUX Plasma defaults on disk"
    assert "login screen config /usr/lib/plasmalogin/plasmalogin.conf.d/50-agentux.conf" \
        test -f /usr/lib/plasmalogin/plasmalogin.conf.d/50-agentux.conf
    assert "cockpit autostart wrapper /usr/libexec/agentux-cockpit-autostart" \
        test -x /usr/libexec/agentux-cockpit-autostart
    assert "/etc/xdg/kded5rc turns kded_plasma_welcome off" \
        bash -c "grep -qx '\[Module-kded_plasma_welcome\]' /etc/xdg/kded5rc && grep -qx 'autoload=false' /etc/xdg/kded5rc"
}

check_user_path() {
    echo "== tools on the user manager's PATH (as user services and Plasma apps see it)"
    local path
    path="$(systemctl --user show-environment | sed -n 's/^PATH=//p')"
    echo "      PATH=$path"
    case ":$path:" in
        *":$HOME/.local/bin:"*) ok "user manager PATH has ~/.local/bin" ;;
        *) bad "user manager PATH lacks ~/.local/bin" ;;
    esac
    case ":$path:" in
        *":$HOME/.local/share/mise/shims:"*) ok "user manager PATH has mise shims" ;;
        *) bad "user manager PATH lacks ~/.local/share/mise/shims" ;;
    esac
    local cmd
    for cmd in claude opencode agy codex bun lazygit ast-grep yq aux; do
        # A transient user service gets exactly the user manager's environment.
        assert "$cmd --version (user service)" \
            systemd-run --user --wait --pipe --quiet --collect -- "$cmd" --version
    done
}

check_agentuxd() {
    echo "== agentuxd (user service)"
    assert "agentuxd.service active" systemctl --user is-active agentuxd.service
    assert "socket $XDG_RUNTIME_DIR/agentux/agentuxd.sock" test -S "$XDG_RUNTIME_DIR/agentux/agentuxd.sock"
    assert "aux ps" aux ps
    local pid
    pid="$(systemctl --user show -P MainPID agentuxd.service)"
    if [[ "$pid" =~ ^[1-9][0-9]*$ ]]; then
        local daemon_path
        daemon_path="$(tr '\0' '\n' <"/proc/$pid/environ" | sed -n 's/^PATH=//p')"
        case ":$daemon_path:" in
            *":$HOME/.local/bin:"*) ok "agentuxd PATH has ~/.local/bin" ;;
            *) bad "agentuxd PATH lacks ~/.local/bin: $daemon_path" ;;
        esac
    fi
}

check_aux_version() {
    echo "== aux version"
    local v
    v="$(aux --version 2>&1)"
    if [[ -z "${EXPECTED_AUX_VERSION:-}" ]]; then
        ok "aux --version  [$v] (no expected version given)"
    elif [[ "$v" =~ (^|[[:space:]])v?${EXPECTED_AUX_VERSION//./\\.}([[:space:]]|$) ]]; then
        ok "aux --version reports $EXPECTED_AUX_VERSION  [$v]"
    else
        bad "aux --version is '$v', expected $EXPECTED_AUX_VERSION"
    fi
}

# Starts `aux daemon --fake-agents` on a socket under $1; sets daemon_pid and
# sock. Fails (and says why) if the socket does not show up.
start_fake_daemon() {
    local tmp="$1"
    sock="$tmp/run/agentuxd.sock"
    aux --socket "$sock" daemon --database "$tmp/state/agentuxd.db" --fake-agents \
        </dev/null >"$tmp/daemon.log" 2>&1 &
    daemon_pid=$!
    if ! wait_for 30 test -S "$sock"; then
        bad "fake-agents daemon socket"; indent <"$tmp/daemon.log"
        kill "$daemon_pid" 2>/dev/null
        return 1
    fi
}

# Commits everything in the git repository $1 as its first commit.
init_repo() {
    git -C "$1" init --quiet --initial-branch=main
    git -C "$1" add .
    git -C "$1" -c user.name="AgentUX Boot Test" -c user.email=boot-test@agentux.invalid \
        commit --quiet --message=init
}

# A run through a second daemon with fake agents on a temporary socket: plan
# (with approval), implement, a gate check and a pull request.
check_fake_run() {
    echo "== end-to-end run with fake agents (aux daemon --fake-agents)"
    local tmp sock repo run_id ps request watched daemon_pid
    tmp="$(mktemp -d)"
    repo="$tmp/repo"
    start_fake_daemon "$tmp" || return
    mkdir -p "$repo"
    cat >"$repo/agentux.yaml" <<'EOF'
version: 1
roles:
  implementer:
    harness: fake
checks:
  - name: check
    run: "true"
pipeline:
  - step: plan
    role: implementer
    approve: true
  - step: implement
    role: implementer
  - step: gate
    checks: [check]
  - step: pull_request
EOF
    init_repo "$repo"

    if ! run_id="$(aux --socket "$sock" run "$repo" --prompt "Boot test run" 2>"$tmp/run.err")"; then
        bad "aux run"; indent <"$tmp/run.err"
    else
        ok "aux run started $run_id"
        if wait_for 60 bash -c "aux --socket '$sock' ps | grep -qx 'WAITING FOR YOU'"; then
            ps="$(aux --socket "$sock" ps)"
            request="$(sed -n '/^WAITING FOR YOU$/{n;p;q}' <<<"$ps" | awk '{print $1}')"
            assert "aux approve $request" aux --socket "$sock" approve "$request" --message "boot test"
            if watched="$(timeout 120 aux --socket "$sock" watch "$run_id" 2>&1)" \
                && grep -q '\[done\]' <<<"$watched"; then
                ok "aux watch: run $run_id done"
            else
                bad "aux watch: run $run_id did not finish"
            fi
            indent <<<"$watched"
        else
            bad "run never waited for plan approval"
            aux --socket "$sock" ps --all 2>&1 | indent
        fi
    fi
    kill "$daemon_pid" 2>/dev/null
    wait "$daemon_pid" 2>/dev/null
    if (( fail )); then echo "      daemon log:"; indent <"$tmp/daemon.log"; fi
    rm -rf "$tmp"
}

# Checks in rootless Podman (isolation.mode: podman, ADR 0009 in
# agentux-os/agentux) on Kinoite with SELinux enforcing. `aux validate` is a
# check; the isolated gate run is a finding: it only warns, with its logs.
check_podman_isolation() {
    echo "== checks isolated in rootless Podman (isolation.mode: podman)"
    local tmp sock repo run_id watched daemon_pid out
    local image=registry.fedoraproject.org/fedora-minimal:44
    tmp="$(mktemp -d)"
    repo="$tmp/repo"
    mkdir -p "$repo"
    cat >"$repo/agentux.yaml" <<EOF
version: 1
isolation:
  mode: podman
  image: $image
roles:
  implementer:
    harness: fake
checks:
  - name: check
    run: "true"
pipeline:
  - step: implement
    role: implementer
  - step: gate
    checks: [check]
EOF
    init_repo "$repo"
    if out="$(aux validate "$repo" 2>&1)" && grep -qi podman <<<"$out" && grep -qF "$image" <<<"$out"; then
        ok "aux validate: checks run in podman with $image"
    else
        bad "aux validate does not show podman isolation with $image"
    fi
    indent <<<"$out"

    echo "      podman: $(podman --version 2>&1); SELinux: $(getenforce 2>&1)"
    echo "      /etc/subuid: $(grep "^$USER:" /etc/subuid 2>&1 || echo "no entry for $USER")"
    echo "      /etc/subgid: $(grep "^$USER:" /etc/subgid 2>&1 || echo "no entry for $USER")"
    echo "      podman info: $(podman info --format 'rootless={{.Host.Security.Rootless}} selinux={{.Host.Security.SELinuxEnabled}} graphDriver={{.Store.GraphDriverName}} network={{.Host.NetworkBackend}} cgroups={{.Host.CgroupsVersion}}' 2>&1 | head -n3)"

    start_fake_daemon "$tmp" || { rm -rf "$tmp"; return; }
    local isolated_ok=0
    if ! run_id="$(aux --socket "$sock" run "$repo" --prompt "Boot test isolated gate" 2>"$tmp/run.err")"; then
        warn "aux run (podman isolation) did not start"; indent <"$tmp/run.err"
    else
        echo "      run $run_id started; waiting up to 15 minutes (the image is pulled first)"
        if watched="$(timeout 900 aux --socket "$sock" watch "$run_id" 2>&1)" \
            && grep -q '\[done\]' <<<"$watched"; then
            ok "isolated gate: run $run_id done"
            isolated_ok=1
        else
            warn "isolated gate: run $run_id did not reach done"
        fi
        indent <<<"$watched"
    fi
    kill "$daemon_pid" 2>/dev/null
    wait "$daemon_pid" 2>/dev/null
    if (( ! isolated_ok )); then
        echo "      daemon log:"; indent <"$tmp/daemon.log"
        echo "      podman ps -a:"; podman ps -a 2>&1 | indent
        echo "      podman images:"; podman images 2>&1 | indent
        echo "      a check by hand (the same podman run as ADR 0009):"
        local wt="$tmp/manual"
        git -C "$repo" worktree add --quiet "$wt" 2>&1 | indent
        podman run --rm --pull=missing --userns=keep-id --security-opt=no-new-privileges --network=none \
            -v "$wt:$wt:Z" -v "$repo/.git:$repo/.git:ro,z" -w "$wt" "$image" \
            sh -c 'id; git --version 2>&1; ls -la' 2>&1 | indent
        echo "      SELinux denials (ausearch -m avc, this boot):"
        sudo ausearch -m avc -ts boot 2>&1 | tail -n 30 | indent
    fi
    podman rmi --force "$image" >/dev/null 2>&1 || true
    rm -rf "$tmp" 2>/dev/null || podman unshare rm -rf "$tmp" 2>/dev/null || true
}

# The Welcome Center (plasma-welcome) is off in the test user's session: the
# kded module that opens it is not loaded and nothing launched it.
check_no_welcome() {
    local out modules bus="unix:path=$XDG_RUNTIME_DIR/bus"
    if out="$(pgrep -a -u "$USER" -x plasma-welcome)"; then
        bad "plasma-welcome is running"; indent <<<"$out"
    else
        ok "plasma-welcome not running"
    fi
    out="$(journalctl --user -b --no-pager -o cat 2>&1 \
        | grep -F -e 'Launching Welcome Center' -e 'app-org.kde.plasma\x2dwelcome@')"
    if [[ -z "$out" ]]; then
        ok "user journal: no \"Launching Welcome Center\", no app-org.kde.plasma\\x2dwelcome@*.service"
    else
        bad "user journal shows the Welcome Center starting"; indent <<<"$out"
    fi
    list_kded_modules() {
        if command -v qdbus6 >/dev/null; then
            DBUS_SESSION_BUS_ADDRESS="$bus" qdbus6 org.kde.kded6 /kded org.kde.kded6.loadedModules
        else
            busctl --user call org.kde.kded6 /kded org.kde.kded6 loadedModules
        fi
    }
    if wait_for 60 list_kded_modules && modules="$(list_kded_modules 2>&1)" && [[ -n "$modules" ]]; then
        if grep -q kded_plasma_welcome <<<"$modules"; then
            bad "kded6 loaded kded_plasma_welcome"
        else
            ok "kded6 has not loaded kded_plasma_welcome  [$(wc -w <<<"$modules") words of loadedModules]"
        fi
    else
        bad "could not list kded6's loaded modules"; indent <<<"$(list_kded_modules 2>&1)"
    fi
}

# Prints the test user's Wayland session id, if there is one.
wayland_session() {
    local id
    for id in $(loginctl list-sessions --no-legend | awk -v u="$USER" '$3 == u {print $1}'); do
        if [[ "$(loginctl show-session "$id" -P Type)" == wayland ]]; then
            echo "$id"; return 0
        fi
    done
    return 1
}

# After an autologin reboot: the graphical session and what it should start.
check_desktop() {
    echo "== desktop session (best effort)"
    local session="" deadline=$(( SECONDS + 240 ))
    until session="$(wayland_session)" || (( SECONDS >= deadline )); do sleep 5; done
    if [[ -n "$session" ]]; then
        ok "wayland session $session for $USER ($(loginctl show-session "$session" -P Desktop))"
    else
        bad "no wayland session for $USER after autologin"
        loginctl list-sessions --no-legend | indent
    fi
    local proc
    for proc in kwin_wayland plasmashell agentux-cockpit; do
        if wait_for 120 pgrep -u "$USER" -x "$proc"; then
            ok "$proc running"
        else
            bad "$proc not running"
        fi
    done
    local pid
    pid="$(pgrep -u "$USER" -x agentux-cockpit | head -n1)"
    if [[ -n "$pid" ]]; then
        local cockpit_path
        cockpit_path="$(tr '\0' '\n' <"/proc/$pid/environ" | sed -n 's/^PATH=//p')"
        case ":$cockpit_path:" in
            *":$HOME/.local/bin:"*) ok "cockpit PATH has ~/.local/bin" ;;
            *) bad "cockpit PATH lacks ~/.local/bin: $cockpit_path" ;;
        esac
    fi
    # For a regular user the autostart wrapper execs the cockpit, so its unit
    # stays active.
    assert 'app-agentux\x2dcockpit@autostart.service active' \
        systemctl --user is-active 'app-agentux\x2dcockpit@autostart.service'
    # The Welcome Center would open some seconds into the session.
    sleep 20
    check_no_welcome
    local laf
    laf="$(kreadconfig6 --group KDE --key LookAndFeelPackage 2>&1)"
    if [[ "$laf" == os.agentux.desktop ]]; then
        ok "look-and-feel is $laf"
    else
        bad "look-and-feel is '$laf', expected os.agentux.desktop"
    fi
    assert "agentuxd.service active after reboot" systemctl --user is-active agentuxd.service
    assert "aux ps after reboot" aux ps
    failed_units --system
    failed_units --user
}

case "$phase" in
    system)
        check_image
        check_system
        check_splash
        check_first_login
        check_antigravity_acp
        check_system_users
        check_wizard_session
        check_desktop_files
        check_aux_version
        check_user_path
        check_agentuxd
        check_fake_run
        check_podman_isolation
        ;;
    desktop)
        check_desktop
        ;;
    sample)
        sample_memory "${2:?unit}" "${3:?marker}"
        ;;
    *)
        echo "unknown phase $phase" >&2; exit 2 ;;
esac
exit "$fail"
