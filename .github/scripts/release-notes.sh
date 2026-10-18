#!/usr/bin/env bash
# Prints the top of a release's notes: its highlights, what changed since the
# previous release, and the AgentUX components it ships. publish-iso.sh puts
# the downloads, verification and images sections after it.
#
# usage: release-notes.sh TAG
#
#   Highlights  docs/releases/TAG.md when there is one (written by hand, in a
#               PR to main: release.yml reads docs/releases from main, so it
#               can land after the tag, while the release's tests run, up to
#               the approval); otherwise the titles of the feature PRs.
#   Changes     the PRs merged since the previous release, from GitHub's
#               generated notes, grouped by their title's prefix (feat, fix,
#               docs, ...) and credited to their authors.
#   Components  the agentux-core and agentux-desktop versions pinned in the
#               Containerfile, and the Fedora release the image is built on.
#
# Preview the notes of the next release before tagging it:
#   GH_REPO=agentux-os/agentux-os .github/scripts/release-notes.sh v0.5.8
# (GitHub generates the changes up to main when TAG does not exist yet.)
set -euo pipefail

tag=${1:?usage: release-notes.sh TAG}
root=$(cd "$(dirname "$0")/../.." && pwd)
repo=${GH_REPO:-${GITHUB_REPOSITORY:-agentux-os/agentux-os}}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The changes start at the previous published release, not the previous tag:
# a tag whose release was rejected or failed (v0.5.7) published nothing, so
# v0.5.8's notes also list what v0.5.7 would have shipped. GitHub lists the
# PRs merged in between as "* <title> by @<author> in <url>/pull/<n>".
previous=$(gh release list -R "$repo" --exclude-drafts --limit 50 --json tagName     --jq "[.[].tagName | select(. != \"$tag\")][0] // empty")
args=(-f tag_name="$tag" -f target_commitish=main)
[[ -n $previous ]] && args+=(-f previous_tag_name="$previous")
gh api "repos/$repo/releases/generate-notes" "${args[@]}" --jq .body >"$work/body"

# "<group>\t<title> (#<n>) by @<author>" for each PR, the conventional prefix
# (feat:, fix(scope):, ...) moved into the group and the title capitalised.
awk '
    /^\* / && / by @[^ ]+ in https:\/\/github\.com\/[^ ]+\/pull\/[0-9]+$/ {
        line = substr($0, 3)
        n = line; sub(/.*\/pull\//, "", n)
        author = line; sub(/ in https:.*/, "", author); sub(/.* by @/, "", author)
        title = line; sub(/ by @[^ ]+ in https:.*/, "", title)
        group = "other"
        if (match(title, /^[a-zA-Z]+(\([^)]*\))?!?: */)) {
            prefix = tolower(substr(title, 1, RLENGTH)); sub(/[(!:].*/, "", prefix)
            title = substr(title, RLENGTH + 1)
            group = prefix
        }
        if (group == "other" && title ~ /^(Pin|Bump) /) group = "deps"
        title = toupper(substr(title, 1, 1)) substr(title, 2)
        printf "%s\t%s ([#%s](https://github.com/'"$repo"'/pull/%s)) by @%s\n", group, title, n, n, author
    }' "$work/body" >"$work/prs"
full=$(grep -o 'https://github.com/[^ ]*/compare/[^ ]*' "$work/body" | head -1 || true)
new=$(grep -o '^\* @[^ ]* made their first contribution.*' "$work/body" || true)

section() { # section TITLE GROUP...
    local title=$1
    shift
    local re
    re="^($(IFS='|'; echo "$*"))	"
    grep -E "$re" "$work/prs" | cut -f2- >"$work/section" || true
    [[ -s $work/section ]] || return 0
    echo "### $title"
    echo
    sed 's/^/- /' "$work/section"
    echo
}

if [[ -f $root/docs/releases/$tag.md ]]; then
    cat "$root/docs/releases/$tag.md"
    echo
elif grep -q '^feat	' "$work/prs"; then
    echo "## Highlights"
    echo
    grep '^feat	' "$work/prs" | cut -f2- | sed 's/ (\[#.*//; s/^/- **/; s/$/**/'
    echo
fi

if [[ -s $work/prs ]]; then
    echo "## What's changed"
    echo
    section "✨ Features" feat
    section "🐛 Fixes" fix
    section "📦 AgentUX components" deps
    section "⚡ Performance" perf
    section "📚 Documentation" docs
    section "🧪 Tests" test
    section "🔧 Build, CI and maintenance" build ci chore refactor style revert
    section "Other changes" other
fi
if [[ -n $new ]]; then
    echo "### 👋 New contributors"
    echo
    echo "${new//\* /- }"
    echo
fi

core=$(sed -n 's/^ARG AGENTUX_CORE_VERSION=//p' "$root/Containerfile")
desktop=$(sed -n 's/^ARG AGENTUX_DESKTOP_VERSION=//p' "$root/Containerfile")
fedora=$(sed -n 's/^ARG FEDORA_VERSION=//p' "$root/Containerfile" | head -1)
echo "## Components"
echo
echo "| Component | Version |"
echo "|---|---|"
[[ -n $core ]] && echo "| agentux-core (\`aux\`, \`agentuxd\`) | [$core](https://github.com/agentux-os/agentux-core/releases/tag/v$core) |"
[[ -n $desktop ]] && echo "| agentux-desktop (cockpit, Welcome) | [$desktop](https://github.com/agentux-os/agentux-desktop/releases/tag/v$desktop) |"
[[ -n $fedora ]] && echo "| Fedora Atomic base | $fedora |"
echo
[[ -n $full ]] && echo "**Full changelog**: $full" && echo
exit 0
