#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
cleanup() {
    rc=$?
    if (( rc != 0 )); then
        echo "profile tests failed (exit $rc, last command: ${BASH_COMMAND})" >&2
    fi
    rm -rf "$tmp"
    exit "$rc"
}
trap cleanup EXIT

export AGENTUX_PROFILE_ROOT="$tmp/root"
export AGENTUX_PROFILE_STATE="$tmp/state/profile.json"
export AGENTUX_PROFILE_CATALOG="$here/files/usr/share/agentux/profiles/catalog.json"
mkdir -p "$tmp/root" "$tmp/state"

show_state="$(bash "$here/files/usr/bin/agentux" profile show)"
grep -q '"requested":null' <<<"$show_state"

show="$(bash "$here/files/usr/bin/agentux" profile plan workstation)"
grep -q '"profile":"workstation"' <<<"$show"
grep -q '"node"' <<<"$show"
grep -q '"desktop"' <<<"$show"

custom="$(bash "$here/files/usr/bin/agentux" profile plan custom --components node,desktop)"
grep -q '"components":\["desktop","node"\]' <<<"$custom"

bash "$here/files/usr/bin/agentux" profile apply workstation >/dev/null
test -s "$AGENTUX_PROFILE_STATE"
grep -q '"applied":\["node","desktop"\]' "$AGENTUX_PROFILE_STATE"

before="$(sha256sum "$AGENTUX_PROFILE_STATE")"
bash "$here/files/usr/bin/agentux" profile apply workstation >/dev/null
after="$(sha256sum "$AGENTUX_PROFILE_STATE")"
test "$before" = "$after"

if bash "$here/files/usr/bin/agentux" profile apply not-a-profile >/dev/null 2>&1; then
    echo "unknown profile was accepted" >&2
    exit 1
fi
test "$before" = "$(sha256sum "$AGENTUX_PROFILE_STATE")"

if bash "$here/files/usr/bin/agentux" profile apply command >/dev/null 2>&1; then
    echo "unconfigured Command profile was accepted" >&2
    exit 1
fi
grep -q '"status":"failed"' "$AGENTUX_PROFILE_STATE"
grep -q '"applied":\["node","desktop"\]' "$AGENTUX_PROFILE_STATE"

bash "$here/files/usr/bin/agentux" profile seed node
test -s "$tmp/state/profile-intent.json"
bash "$here/files/usr/bin/agentux" profile apply-intent >/dev/null
test ! -e "$tmp/state/profile-intent.json"
grep -q '"requested":"node"' "$AGENTUX_PROFILE_STATE"

if bash "$here/files/usr/bin/agentux" profile apply command >/dev/null 2>"$tmp/command-error"; then
    echo "unconfigured Command profile was accepted" >&2
    exit 1
fi
grep -q '"status":"failed"' "$AGENTUX_PROFILE_STATE"
grep -q 'command-server' "$AGENTUX_PROFILE_STATE"

if bash "$here/files/usr/bin/agentux" profile apply workstation >/dev/null 2>&1; then
    if bash "$here/files/usr/bin/agentux" profile remove node >/dev/null 2>&1; then
        echo "node removal was accepted while desktop depends on it" >&2
        exit 1
    fi
fi

echo "profile tests passed"
