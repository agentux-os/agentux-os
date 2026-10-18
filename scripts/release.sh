#!/usr/bin/env bash
# Tags a release of main: scripts/release.sh 0.5.2 (or `just release 0.5.2`).
#
# A release promotes the image that main already built and tested for the
# tagged commit (sha-<commit>, see release.yml), so this checks that both
# images exist for origin/main's HEAD before it pushes v<version>. Then
# release.yml boots that image, builds and tests the ISOs, and waits for the
# owner's approval (scripts/approve.sh). Needs git, curl and push rights to
# v* tags (the "Release tags" ruleset allows only admins).
set -euo pipefail

repo=agentux-os/agentux-os
version="${1:?usage: release.sh VERSION (e.g. 0.5.2)}"
version="${version#v}"
if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
    echo "not a version: $version" >&2
    exit 1
fi
tag="v$version"

git fetch --quiet --tags origin main
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    echo "$tag already exists; releases are never re-tagged, pick the next version" >&2
    exit 1
fi
commit="$(git rev-parse origin/main)"
short="${commit:0:12}"

for image in agentux; do
    token="$(curl -fsS "https://ghcr.io/token?scope=repository:agentux-os/$image:pull" |
        sed -E 's/.*"token":"([^"]+)".*/\1/')"
    code="$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $token" \
        -H 'Accept: application/vnd.oci.image.index.v1+json' \
        "https://ghcr.io/v2/agentux-os/$image/manifests/sha-$short")"
    if [[ $code != 200 ]]; then
        echo "ghcr.io/agentux-os/$image:sha-$short is not published (HTTP $code)." >&2
        echo "Wait for main's Build image run: https://github.com/$repo/actions/workflows/build.yml" >&2
        exit 1
    fi
done

echo "Release $tag of main at $(git log -1 --format='%h %s' "$commit")"
echo "Image: ghcr.io/agentux-os/agentux:sha-$short (published)"
if git describe --tags --abbrev=0 --match 'v*' "$commit" >/dev/null 2>&1; then
    prev="$(git describe --tags --abbrev=0 --match 'v*' "$commit")"
    echo "Changes since $prev:"
    git log --format='  %h %s' "$prev..$commit"
fi
read -rp "Push $tag? [y/N] " ok
[[ $ok == [yY] ]] || { echo "nothing pushed"; exit 1; }
git tag -a "$tag" -m "AgentUX $version" "$commit"
git push origin "$tag"
echo "Release run: https://github.com/$repo/actions/workflows/release.yml"
echo "When its tests pass, approve it: scripts/approve.sh"
