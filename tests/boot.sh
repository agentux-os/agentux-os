#!/usr/bin/bash
# Boot test checks, run inside a booted AgentUX VM as the test user (over SSH,
# with passwordless sudo) by tests/boot-vm.sh:
#   boot.sh system   the booted image, system and user units, first login,
#                    agentuxd and an end-to-end run with fake agents
#   boot.sh desktop  after an autologin reboot: the Plasma session and the
#                    cockpit (reported, but boot-vm.sh does not fail on them)
# EXPECTED_IMAGE is the image reference the system should have booted. An
# optional GITHUB_TOKEN is used only to retry a failed first login (mise
# resolves versions through the GitHub API, which CI runners share).
set -uo pipefail

phase="${1:?usage: boot.sh system|desktop}"
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

failed_units() {
    # $1: --system or --user
    local units unit
    units="$(systemctl "$1" --failed --plain --no-legend 2>&1 | awk '{print $1}')"
    if [[ -z "$units" ]]; then
        ok "systemctl $1 --failed is empty"
        return
    fi
    for unit in $units; do
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

check_system() {
    echo "== system units"
    local state
    state="$(timeout 300 systemctl is-system-running --wait 2>&1)"
    echo "      system state: $state"
    failed_units --system
    assert "display manager active" systemctl is-active display-manager.service
}

# Polls agentux-first-login.service until it finished, failed for good, failed
# once and waits to restart, or `limit` seconds passed. Meanwhile samples its
# cgroup: the largest anonymous memory seen (what MemoryHigh cannot reclaim
# without swap) and how often it went over MemoryHigh. Sets st and sub.
watch_first_login() {
    local unit="$1" limit="$2" start=$SECONDS cg anon high
    while true; do
        st="$(systemctl --user show -P ActiveState "$unit")"
        sub="$(systemctl --user show -P SubState "$unit")"
        cg="/sys/fs/cgroup$(systemctl --user show -P ControlGroup "$unit")"
        if [[ "$cg" != /sys/fs/cgroup && -r "$cg/memory.stat" ]]; then
            anon="$(awk '$1 == "anon" {print $2}' "$cg/memory.stat")"
            (( ${anon:-0} > anon_max )) && anon_max="$anon"
            high="$(awk '$1 == "high" {print $2}' "$cg/memory.events")"
            [[ -n "$high" ]] && high_events="$high"
        fi
        [[ "$st" == inactive && -e "$marker" ]] && return
        [[ "$st" == failed || "$sub" == auto-restart ]] && return
        (( SECONDS - start >= limit )) && return
        sleep 5
    done
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
    local limit="${FIRST_LOGIN_TIMEOUT:-1800}" st="" sub="" anon_max=0 high_events=""
    echo "      waiting up to ${limit}s for $unit"
    watch_first_login "$unit" "$limit"
    echo "      $unit: $st/$sub, result $(systemctl --user show -P Result "$unit"), restarts $(systemctl --user show -P NRestarts "$unit"), ran $(systemctl --user show -P ExecMainStartTimestamp "$unit") .. $(systemctl --user show -P ExecMainExitTimestamp "$unit")"
    if [[ ! -e "$marker" && -n "${GITHUB_TOKEN:-}" ]]; then
        warn "first login did not complete on its own; its log:"
        journalctl --user -u "$unit" --no-pager -o cat -n 40 | indent
        echo "      retrying now with GITHUB_TOKEN in the user manager environment"
        systemctl --user set-environment GITHUB_TOKEN="$GITHUB_TOKEN"
        systemctl --user reset-failed "$unit"
        systemctl --user start --no-block "$unit"
        sleep 5
        watch_first_login "$unit" "$limit"
        systemctl --user unset-environment GITHUB_TOKEN
    fi
    if [[ -e "$marker" ]]; then
        ok "$unit completed (marker $marker)"
    else
        bad "$unit did not complete"
        journalctl --user -u "$unit" --no-pager -o cat -n 60 | indent
    fi
    # systemd logs what each run used when it stops; the last one is the run
    # that completed.
    local used
    used="$(journalctl --user -u "$unit" --no-pager -o cat \
        | sed -n 's/^.*: Consumed //p' | tail -n1)"
    echo "      used: ${used:-?}"
    metric "first-login run" "${used:-?}"
    metric "first-login largest anon memory (sampled every 5 s)" \
        "$(( anon_max / 1048576 ))M, MemoryHigh=$(systemctl --user show -P MemoryHigh "$unit"), over it ${high_events:-?} times"
    failed_units --user
}

# The units are enabled globally, so every user manager gets them, including
# those of system users with a session (plasma-setup's first-boot wizard).
# Their messages in the journal carry the manager's UID.
check_system_users() {
    echo "== AgentUX user units only run for regular users"
    local uid_min unit uids u
    uid_min="$(awk '$1 == "UID_MIN" {print $2}' /etc/login.defs)"
    for unit in agentux-first-login.service agentuxd.service 'app-agentux\x2dcockpit@autostart.service'; do
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
        elif [[ "$unit" == app-* ]]; then
            # The cockpit autostart comes from agentux-desktop's Plasma overlay.
            warn "$unit also started for system users: ${system_uids[*]}"
        else
            bad "$unit also ran for system users: ${system_uids[*]}"
        fi
    done
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

# A run through a second daemon with fake agents on a temporary socket: plan
# (with approval), implement, a gate check and a pull request.
check_fake_run() {
    echo "== end-to-end run with fake agents (aux daemon --fake-agents)"
    local tmp sock repo run_id ps request watched daemon_pid
    tmp="$(mktemp -d)"
    sock="$tmp/run/agentuxd.sock"
    repo="$tmp/repo"
    aux --socket "$sock" daemon --database "$tmp/state/agentuxd.db" --fake-agents \
        </dev/null >"$tmp/daemon.log" 2>&1 &
    daemon_pid=$!
    if ! wait_for 30 test -S "$sock"; then
        bad "fake-agents daemon socket"; indent <"$tmp/daemon.log"
        kill "$daemon_pid" 2>/dev/null; return
    fi
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
    git -C "$repo" init --quiet --initial-branch=main
    git -C "$repo" add .
    git -C "$repo" -c user.name="AgentUX Boot Test" -c user.email=boot-test@agentux.invalid \
        commit --quiet --message=init

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
        check_first_login
        check_system_users
        check_user_path
        check_agentuxd
        check_fake_run
        ;;
    desktop)
        check_desktop
        ;;
    *)
        echo "unknown phase $phase" >&2; exit 2 ;;
esac
exit "$fail"
