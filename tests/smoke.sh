#!/usr/bin/bash
# Smoke test for the AgentUX image, run as root inside a container of it:
#   podman run --rm -v ./tests:/tests:ro,z <image> /tests/smoke.sh
# Creates a regular user, runs first-login as that user for real (needs
# network), bounded by its unit's TimeoutStartSec, and checks that every tool
# resolves from a clean login shell. Then installs Antigravity's ACP server
# the way its own unit does (warnings only). Step timings go to the log and,
# if SMOKE_SUMMARY names a file, to it as Markdown.
set -euo pipefail

user=agentux-smoke
home=/var/home/$user

mkdir -p /var/home
useradd --create-home --home-dir "$home" "$user"

# Run as the user with a clean environment, like the systemd user service.
# A GITHUB_TOKEN, if given, spares mise's GitHub downloads the anonymous rate
# limit shared by CI runners.
user_env=(HOME="$home" USER="$user" LOGNAME="$user" SHELL=/usr/bin/bash
          TERM=dumb PATH=/usr/local/bin:/usr/bin)
[[ -n "${GITHUB_TOKEN:-}" ]] && user_env+=(GITHUB_TOKEN="$GITHUB_TOKEN")
as_user() {
    runuser -u "$user" -- env -i "${user_env[@]}" "$@"
}

fail=0
units=/usr/lib/systemd/user
state=$home/.local/state/agentux
# SMOKE_SUMMARY, if set, is a Markdown file that gets the timings.
summary="${SMOKE_SUMMARY:-/dev/null}"

# TimeoutStartSec= of a unit file in seconds (s, min and h suffixes).
unit_timeout() {
    local v
    v="$(sed -n 's/^TimeoutStartSec=//p' "$units/$1")"
    case "$v" in
        *min) echo $(( ${v%min} * 60 )) ;;
        *h)   echo $(( ${v%h} * 3600 )) ;;
        *s)   echo "${v%s}" ;;
        [0-9]*) echo "$v" ;;
        *)    echo 0 ;;
    esac
}

# timed_run MODE UNIT: runs `first-login MODE` as the user, bounded by the
# unit's TimeoutStartSec as systemd would, and reports each step's time.
# Sets run_rc, run_took and run_budget.
timed_run() {
    local mode="$1" unit="$2" budget
    budget="$(unit_timeout "$unit")"
    if (( budget <= 0 )); then
        echo "::error::$unit has no TimeoutStartSec"
        fail=1 budget=3600
    fi
    local start=$SECONDS
    echo "::group::first-login $mode (budget ${budget}s, $unit TimeoutStartSec)"
    run_rc=0
    as_user timeout --kill-after=30 "$budget" /usr/libexec/agentux/first-login "$mode" || run_rc=$?
    run_took=$(( SECONDS - start ))
    run_budget=$budget
    echo "::endgroup::"
    local steps="$state/$mode.steps" name result took step_budget sum=0
    echo "== first-login $mode: ${run_took}s of ${budget}s, exit $run_rc"
    {
        echo "### first-login $mode: ${run_took}s of ${budget}s (exit $run_rc)"
        echo
        echo "| Step | Result | Seconds | Budget |"
        echo "|---|---|---|---|"
    } >>"$summary"
    if [[ -r "$steps" ]]; then
        while IFS=$'\t' read -r name result took step_budget; do
            printf '      %-24s %-8s %5ss of %ss\n' "$name" "$result" "$took" "$step_budget"
            echo "| $name | $result | $took | $step_budget |" >>"$summary"
            sum=$(( sum + step_budget ))
        done <"$steps"
    fi
    echo >>"$summary"
    # nm-online's 60s come first in the unit; the steps' budgets must fit
    # after it, or systemd would kill a run that is still within them.
    if (( sum + 60 > budget )); then
        echo "::error::$unit TimeoutStartSec=${budget}s is less than its steps' budgets (${sum}s) plus nm-online's 60s"
        fail=1
    fi
}

timed_run first-login agentux-first-login.service
if (( run_rc == 124 || run_rc == 137 )); then
    echo "::error::first-login did not finish within ${run_budget}s"; fail=1
elif (( run_rc != 0 )); then
    echo "::error::first-login failed (exit $run_rc)"; fail=1
fi

check() {
    local cmd="$1"
    local out
    if out="$(as_user bash -lc "$cmd" 2>&1 </dev/null)"; then
        printf 'ok    %-28s %s\n' "$cmd" "$(head -n1 <<<"$out")"
    else
        printf 'FAIL  %-28s %s\n' "$cmd" "$out"
        fail=1
    fi
}

echo "== marker"
check 'test -e ~/.local/state/agentux/first-login.done'

echo "== per-user tools (login shell)"
for cmd in claude opencode agy codex bun lazygit ast-grep yq; do
    check "$cmd --version"
done

echo "== system toolchain"
for cmd in git gh rg fd jq bat delta just uv node npm mise distrobox podman; do
    check "command -v $cmd"
done

echo "== AgentUX (agentux-core, agentux-desktop)"
# Checks run as root: a description and a command, which must succeed.
assert() {
    local what="$1"; shift
    local out
    if out="$("$@" 2>&1)"; then
        printf 'ok    %-44s %s\n' "$what" "$(head -n1 <<<"$out")"
    else
        printf 'FAIL  %-44s %s\n' "$what" "$out"
        fail=1
    fi
}
for bin in aux agentuxd agentux-cockpit; do
    assert "/usr/bin/$bin" test -x "/usr/bin/$bin"
done
check 'aux --version'
check 'agentuxd --version'
assert "Plasma look-and-feel os.agentux.desktop" \
    test -e /usr/share/plasma/look-and-feel/os.agentux.desktop/metadata.json
assert "kdeglobals selects the AgentUX theme" \
    grep -qx 'LookAndFeelPackage=os.agentux.desktop' /etc/xdg/kdeglobals
assert "agentuxd enabled for all users" \
    test -L /etc/systemd/user/default.target.wants/agentuxd.service
assert "agentux-first-login enabled for all users" \
    test -L /etc/systemd/user/default.target.wants/agentux-first-login.service
assert "agentux-antigravity-acp enabled for all users" \
    test -L /etc/systemd/user/default.target.wants/agentux-antigravity-acp.service

# Start the daemon as the user, the way its user unit does, and talk to it.
runtime_dir="$(mktemp -d)"
chown "$user:" "$runtime_dir"
chmod 0700 "$runtime_dir"
sock="$runtime_dir/agentux/agentuxd.sock"
fail_before=$fail fail=0
as_user env XDG_RUNTIME_DIR="$runtime_dir" agentuxd </dev/null >"$runtime_dir.log" 2>&1 &
for _ in $(seq 50); do
    [[ -S "$sock" ]] && break
    sleep 0.2
done
assert "agentuxd socket $sock" test -S "$sock"
check "XDG_RUNTIME_DIR=$runtime_dir aux ps"
pkill -u "$user" -x agentuxd || true
wait || true
if (( fail )); then
    echo "agentuxd log:"; cat "$runtime_dir.log"
fi
fail=$(( fail | fail_before ))

# The user manager's environment (user services, apps started by Plasma)
# gets PATH from environment.d, not from /etc/profile.d.
assert "/usr/lib/environment.d/60-agentux.conf" test -f /usr/lib/environment.d/60-agentux.conf
envgen=/usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator
if [[ -x "$envgen" ]]; then
    user_path="$(as_user "$envgen" | sed -n 's/^PATH=//p')"
    assert "environment.d PATH has ~/.local/bin" \
        grep -q "^$home/.local/bin:$home/.local/share/mise/shims:" <<<"$user_path"
    echo "      user manager PATH: $user_path"
else
    echo "::warning::$envgen not found; environment.d not resolved"
fi

# Antigravity's ACP server has a lower-priority unit of its own; it is
# optional, so a failure or timeout here only warns.
timed_run antigravity-acp agentux-antigravity-acp.service
if (( run_rc == 124 || run_rc == 137 )); then
    echo "::warning::Antigravity ACP server did not finish within ${run_budget}s"
elif (( run_rc != 0 )); then
    echo "::warning::Antigravity ACP server install failed (exit $run_rc)"
fi

echo "== optional ACP extras (warnings only)"
for cmd in claude-agent-acp codex-acp agy-acp-server; do
    if as_user bash -lc "test -x \"\$(command -v $cmd)\"" </dev/null; then
        echo "ok    $cmd"
    else
        echo "::warning::optional $cmd not installed"
    fi
done

exit "$fail"
