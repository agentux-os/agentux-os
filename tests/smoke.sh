#!/usr/bin/bash
# Smoke test for the AgentUX image, run as root inside a container of it:
#   podman run --rm -v ./tests:/tests:ro,z <image> /tests/smoke.sh
# Creates a regular user, runs first-login as that user for real (needs
# network), bounded by its unit's TimeoutStartSec, and checks that every tool
# resolves from a clean login shell. Then installs Antigravity's ACP server
# the way its own unit does (warnings only). Step timings go to the log and,
# if SMOKE_SUMMARY names a file, to it as Markdown. SMOKE_VARIANT (plasma or
# hyprland) is the image variant expected; the hyprland one
# also gets its Hyprland session and defaults checked.
set -euo pipefail

# Without SMOKE_VARIANT (`just smoke`), the image's own os-release says which.
variant="${SMOKE_VARIANT:-$(grep -qxE 'VARIANT_ID="?agentux-hyprland"?' /etc/os-release && echo hyprland || echo plasma)}"
case "$variant" in
    plasma) image_id=agentux ;;
    hyprland) image_id=agentux-hyprland ;;
    *) echo "SMOKE_VARIANT must be plasma or hyprland" >&2; exit 2 ;;
esac

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
# The system calls itself AgentUX but keeps Fedora's ID and version fields
# (see the Containerfile). The inner bash expands the variables.
# shellcheck disable=SC2016
assert "os-release NAME=AgentUX, VARIANT_ID=IMAGE_ID=$image_id, LOGO=agentux" \
    env image_id="$image_id" bash -c '. /etc/os-release && [[ $NAME == AgentUX && $VARIANT_ID == "$image_id" && $IMAGE_ID == "$image_id" && $LOGO == agentux && $PRETTY_NAME == "AgentUX "* ]] && echo "$PRETTY_NAME"'
# shellcheck disable=SC2016
assert "os-release ID=fedora" bash -c '. /etc/os-release && test "$ID" = fedora'
# The kept fields as the base image had them (the Containerfile saves its
# os-release); one the base lacks, like Fedora 44's PLATFORM_ID, stays absent.
for key in ID VERSION_ID PLATFORM_ID CPE_NAME SUPPORT_END; do
    assert "os-release $key as in the base image" \
        bash -c "test \"\$(grep '^$key=' /etc/os-release)\" = \"\$(grep '^$key=' /usr/share/agentux/os-release.base)\" && { grep '^$key=' /etc/os-release || echo '(not set in either)'; }"
done
assert "agentux icon in hicolor and pixmaps" \
    test -f /usr/share/icons/hicolor/scalable/apps/agentux.svg -a -f /usr/share/icons/hicolor/256x256/apps/agentux.png -a -f /usr/share/pixmaps/agentux.png
assert "kcm-about-distrorc uses the AgentUX logo" \
    grep -qx 'LogoPath=/usr/share/icons/hicolor/256x256/apps/agentux.png' /etc/xdg/kcm-about-distrorc
# plasma-setup's first-boot wizard loads its background from Fedora's Default
# wallpaper package, which the Containerfile points at AgentUX's.
for f in images/5120x2880.jxl images/1440x2960.jxl images_dark/5120x2880.jxl images_dark/1440x2960.jxl; do
    assert "wallpapers/Default/contents/$f is AgentUX's" \
        test "$(readlink -f "/usr/share/wallpapers/Default/contents/$f")" = "/usr/share/wallpapers/AgentUX-Default/contents/$f"
done
assert "agentuxd enabled for all users" \
    test -L /etc/systemd/user/default.target.wants/agentuxd.service
assert "agentux-first-login enabled for all users" \
    test -L /etc/systemd/user/default.target.wants/agentux-first-login.service
assert "agentux-antigravity-acp enabled for all users" \
    test -L /etc/systemd/user/default.target.wants/agentux-antigravity-acp.service

# Waybar's agents module (hyprland variant): /usr/libexec/agentux/waybar-agents
# must print one valid Waybar JSON object whatever the daemon's state. With
# no daemon it says offline; against `aux daemon --fake-agents` on a
# temporary socket it says idle, then, once a run waits for plan approval,
# waiting with one run and one request.
waybar_agents() {
    echo "== Waybar agents module (waybar-agents)"
    local wb=/usr/libexec/agentux/waybar-agents tmp sock repo i
    assert "$wb executable" test -x "$wb"
    # shellcheck disable=SC2016 # jq's variables
    assert "waybar config runs $wb as JSON" \
        jq -e --arg wb "$wb" '."custom/agents".exec == $wb and ."custom/agents"."return-type" == "json" and (."modules-left" + ."modules-center" + ."modules-right" | index("custom/agents"))' \
        "$home/.config/waybar/config.jsonc"
    tmp="$(mktemp -d)"
    chown "$user:" "$tmp"
    chmod 0700 "$tmp"
    sock="$tmp/run/agentuxd.sock"
    # as_user with the socket; the output must be a JSON object of class $1.
    # shellcheck disable=SC2317,SC2329 # called through assert
    wb_is() {
        as_user env XDG_RUNTIME_DIR="$tmp" AGENTUX_SOCKET="$sock" "$wb" </dev/null \
            | tee /dev/stderr | jq -e --arg c "$1" '.class == $c and (.text | type == "string") and (.tooltip | type == "string")'
    }
    assert "waybar-agents with no daemon: offline" wb_is offline

    as_user env AGENTUX_SOCKET="$sock" aux daemon --database "$tmp/state/agentuxd.db" --fake-agents \
        </dev/null >"$tmp/daemon.log" 2>&1 &
    local daemon_pid=$!
    for _ in $(seq 100); do
        [[ -S "$sock" ]] && break
        sleep 0.2
    done
    assert "fake-agents daemon socket $sock" test -S "$sock"
    assert "waybar-agents, fake daemon, no runs: idle" wb_is idle

    repo="$tmp/repo"
    mkdir -p "$repo"
    cat >"$repo/agentux.yaml" <<'EOF'
version: 1
roles:
  implementer:
    harness: fake
pipeline:
  - step: plan
    role: implementer
    approve: true
  - step: implement
    role: implementer
EOF
    chown -R "$user:" "$repo"
    as_user git -C "$repo" init --quiet --initial-branch=main
    as_user git -C "$repo" add .
    as_user git -C "$repo" -c user.name="AgentUX Smoke" -c user.email=smoke@agentux.invalid \
        -c commit.gpgsign=false commit --quiet --message=init
    assert "aux run (fake agents)" \
        as_user env AGENTUX_SOCKET="$sock" aux run "$repo" --prompt "Waybar & <smoke> test"
    for i in $(seq 60); do
        as_user env AGENTUX_SOCKET="$sock" aux ps </dev/null | grep -qx 'WAITING FOR YOU' && break
        sleep 1
    done
    echo "      after ${i}s:"
    as_user env AGENTUX_SOCKET="$sock" aux ps </dev/null | sed 's/^/      /' || true
    assert "waybar-agents with a plan to approve: waiting" wb_is waiting
    assert "waybar-agents counts 1 run, 1 waiting" \
        bash -c "runuser -u '$user' -- env -i HOME='$home' PATH=/usr/bin XDG_RUNTIME_DIR='$tmp' AGENTUX_SOCKET='$sock' '$wb' | jq -e '.text == \"agents 1 · 1 waiting\" and (.tooltip | contains(\"&amp; &lt;smoke&gt;\"))'"

    kill "$daemon_pid" 2>/dev/null || true
    wait "$daemon_pid" 2>/dev/null || true
    if (( fail )); then echo "      fake-agents daemon log:"; sed 's/^/      /' "$tmp/daemon.log"; fi
    rm -rf "$tmp"
}

# The hyprland variant: Hyprland as a second session, preselected on the
# login screen, and the AgentUX defaults seeded into a fresh user's ~/.config
# the way the session does it, which must parse. The plasma image has none of
# it.
hypr_session=/usr/share/wayland-sessions/agentux-hyprland.desktop
if [[ "$variant" == hyprland ]]; then
    echo "== Hyprland (agentux-hyprland)"
    for bin in Hyprland start-hyprland hyprctl hyprlock hypridle waybar fuzzel mako foot swaybg wl-copy cliphist grim slurp nm-applet; do
        assert "$bin" command -v "$bin"
    done
    assert "hyprpolkitagent user unit" test -f /usr/lib/systemd/user/hyprpolkitagent.service
    assert "xdg-desktop-portal-hyprland" test -f /usr/share/xdg-desktop-portal/hyprland-portals.conf
    assert "session $hypr_session runs hyprland-session" \
        grep -qx 'Exec=/usr/libexec/agentux/hyprland-session' "$hypr_session"
    assert "plasma.desktop still installed" test -f /usr/share/wayland-sessions/plasma.desktop
    assert "login screen preselects agentux-hyprland.desktop" \
        grep -qx 'PreselectedSession=agentux-hyprland.desktop' /usr/lib/plasmalogin/plasmalogin.conf.d/60-agentux-hyprland.conf
    assert "COPR repository disabled" \
        bash -c '! grep -qx "enabled=1" /etc/yum.repos.d/_copr_sdegler-hyprland.repo'
    assert "seed ~/.config (hyprland-defaults)" as_user /usr/libexec/agentux/hyprland-defaults
    for f in hypr/hyprland.conf hypr/hyprlock.conf hypr/hypridle.conf waybar/config.jsonc waybar/style.css mako/config fuzzel/fuzzel.ini foot/foot.ini; do
        assert "seeded .config/$f" test -f "$home/.config/$f"
    done
    # A second run keeps what is there.
    echo '# mine' >>"$home/.config/foot/foot.ini"
    assert "hyprland-defaults again" as_user /usr/libexec/agentux/hyprland-defaults
    assert "hyprland-defaults kept the user's foot.ini" \
        bash -c "tail -n1 '$home/.config/foot/foot.ini' | grep -qx '# mine'"
    hypr_runtime="$(mktemp -d)"
    chown "$user:" "$hypr_runtime"
    chmod 0700 "$hypr_runtime"
    assert "Hyprland --verify-config on the seeded hyprland.conf" \
        bash -c "runuser -u '$user' -- env HOME='$home' XDG_RUNTIME_DIR='$hypr_runtime' Hyprland --verify-config --config '$home/.config/hypr/hyprland.conf' 2>&1 | tee /dev/stderr | grep -qx 'config ok'"
    assert "foot --check-config on the seeded foot.ini" \
        as_user foot --check-config --config "$home/.config/foot/foot.ini"
    rm -rf "$hypr_runtime"
    waybar_agents
else
    assert "no Hyprland session in the plasma image" test ! -e "$hypr_session"
fi

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

# The welcome wizard's backend (agentux-desktop's /usr/libexec/agentux-setup)
# and its catalog: the catalog parses, a dry run prints the commands the
# wizard shows, the first-run marker decides whether it opens at login, the
# user's Flathub remote can be added from the shipped repo file, and a real
# install through the script (Flatseal, a small Flatpak; kubectl with mise)
# works where the container allows it (those two only warn).
welcome_wizard() {
    echo "== welcome wizard (agentux-setup)"
    local setup=/usr/libexec/agentux-setup catalog=/usr/share/agentux/setup/catalog.json out
    assert "$setup executable" test -x "$setup"
    assert "catalog $catalog parses, with items" jq -e '(.items | length) > 20 and (.categories | length) > 5' "$catalog"
    assert "Flathub repo file" grep -qx 'Url=https://dl.flathub.org/repo/' /usr/share/agentux/setup/flathub.flatpakrepo
    assert "login autostart runs agentux-setup autostart" \
        grep -qx 'Exec=/usr/libexec/agentux-setup autostart' /etc/xdg/autostart/agentux-welcome.desktop
    assert "app menu entry reopens the wizard" \
        grep -qx 'Exec=agentux-cockpit --welcome' /usr/share/applications/agentux-welcome.desktop
    out="$(as_user "$setup" install --dry-run vscode java@temurin-17 intellij-idea fedora-dev 2>&1 </dev/null)"
    printf '%s\n' "$out" | sed 's/^/      /'
    local line
    for line in \
        $'vscode\tflatpak install --user --noninteractive --or-update flathub com.visualstudio.code' \
        $'vscode\tflatpak override --user --talk-name=org.freedesktop.Flatpak --filesystem=home com.visualstudio.code' \
        $'java\tmise use --global java@temurin-17' \
        $'intellij-idea\tagentux-setup jetbrains-toolbox' \
        "fedora-dev"$'\t'"agentux-setup distrobox-create fedora-dev registry.fedoraproject.org/fedora-toolbox:$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"')"; do
        assert "dry run: ${line//$'\t'/: }" grep -qxF "$line" <<<"$out"
    done
    assert "dry run refuses an unknown item" bash -c "! runuser -u '$user' -- '$setup' plan no-such-item 2>/dev/null"
    # A regular user without the marker gets the wizard; after finish, not again.
    check "$setup should-run"
    check "$setup finish && ! $setup should-run && $setup reset && $setup should-run"
    assert "distrobox installed (Distrobox items)" command -v distrobox
    if command -v toolbox >/dev/null; then echo "ok    toolbox installed"; else echo "::warning::toolbox is not installed"; fi
    if command -v firefox >/dev/null; then echo "      firefox: $(command -v firefox) (preinstalled)"; else echo "      firefox: not installed"; fi
    echo "      system flatpak remotes:"
    flatpak remotes --system --show-disabled --columns=name,options,url 2>&1 | sed 's/^/        /'

    # The user's Flathub remote, as every Flatpak item adds it.
    check "flatpak remote-add --user --if-not-exists flathub /usr/share/agentux/setup/flathub.flatpakrepo"
    check "flatpak remotes --user --columns=name | grep -qx flathub"

    # Real installs through the script, warnings only: network and the
    # container (no user namespaces for bwrap, no D-Bus) may not allow them.
    local item status
    for item in flatseal kubectl; do
        if out="$(as_user timeout 900 "$setup" install "$item" 2>&1 </dev/null)"; then
            echo "ok    agentux-setup install $item"
            # What the wizard then shows: the item done, and found installed.
            status="$(as_user "$setup" status --scan </dev/null)"
            assert "status: $item done and installed" \
                jq -e --arg i "$item" '.items[$i].state == "done" and (.installed | index($i))' <<<"$status"
        else
            echo "::warning::agentux-setup install $item failed: $(tail -n 3 "$state/setup/logs/$item.log" 2>/dev/null | tr '\n' ' ')"
        fi
    done
    as_user "$setup" status --scan </dev/null | jq -c '{flathub, items: (.items | map_values(.state)), installed}' | sed 's/^/      status: /' || true
    as_user bash -lc 'kubectl version --client 2>/dev/null | head -n 1' </dev/null | sed 's/^/      /' || true
}
welcome_wizard

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
