#!/usr/bin/bash
# Smoke test for the AgentUX image, run as root inside a container of it:
#   podman run --rm -v ./tests:/tests:ro,z <image> /tests/smoke.sh
# Creates a regular user, runs first-login as that user for real (needs
# network) and checks that every tool resolves from a clean login shell.
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
echo "::group::first-login"
as_user /usr/libexec/agentux/first-login || { echo "::error::first-login failed"; fail=1; }
echo "::endgroup::"

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

echo "== optional ACP extras (warnings only)"
for cmd in claude-agent-acp codex-acp agy-acp-server; do
    if as_user bash -lc "test -x \"\$(command -v $cmd)\"" </dev/null; then
        echo "ok    $cmd"
    else
        echo "::warning::optional $cmd not installed"
    fi
done

exit "$fail"
