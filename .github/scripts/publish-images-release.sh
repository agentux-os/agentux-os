#!/usr/bin/env bash
# Publishes a release that ships no ISOs: a component bump's patch tag, which
# patch-tag.yml marks "Release-ISOs: none" (see release.yml). It runs once the
# owner approved the release and :<tag> and :stable point at its images.
#
# usage: publish-images-release.sh
#
# Creates the GitHub release, whose downloads point at the newest ISOs (the
# release latest.json names, in iso/stable/), and rebuilds releases.json, so
# agentux-version names this release on systems that updated to it. iso/ and
# latest.json stay as they are: the newest ISOs install their own release and
# then follow :stable, so the first `bootc upgrade` brings this one.
#
# Environment: R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY,
# COSIGN_PRIVATE_KEY, COSIGN_PASSWORD, GH_TOKEN, as publish-iso.sh's release
# mode.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
export GH_REPO=${GH_REPO:-${GITHUB_REPOSITORY:-agentux-os/agentux-os}}
bucket=agentux-downloads
base=https://download.agentuxos.org

if [[ ${GITHUB_REF:-} != refs/tags/v* ]]; then
    echo "::error::a release needs a v* tag (GITHUB_REF=${GITHUB_REF:-})"
    exit 1
fi
tag=$GITHUB_REF_NAME
for v in R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY COSIGN_PRIVATE_KEY; do
    if [[ -z ${!v:-} ]]; then
        echo "::error::$v is not set; cannot publish (the secrets live in the release environment)"
        exit 1
    fi
done

command -v aws >/dev/null || sudo snap install aws-cli --classic
export AWS_ACCESS_KEY_ID=$R2_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$R2_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION=auto
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
endpoint="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
s3() {
    local attempt
    for attempt in 1 2 3 4; do
        aws s3 --endpoint-url "$endpoint" --only-show-errors "$@" && return 0
        echo "s3 $1: attempt $attempt failed, retrying" >&2
        sleep $((attempt * 10))
    done
    return 1
}
short="public, max-age=300"
sign() { cosign sign-blob --yes --key env://COSIGN_PRIVATE_KEY --bundle "$1.sigstore.json" "$1" >/dev/null; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"

# The release whose ISOs are the newest, the one iso/stable/ holds.
isos=$(curl -fsS "$base/latest.json" | jq -r .version)
[[ $isos == v* ]] || { echo "::error::latest.json names no release"; exit 1; }

# ---- the GitHub release ------------------------------------------------------

pre=()
# Pre-releases while AgentUX is pre-1.0.
[[ $tag == v0.* ]] && pre=(--prerelease)
bash "$here/release-notes.sh" "$tag" >notes.md
cat >>notes.md <<EOF
## Downloads

This release ships no new ISOs: it updates AgentUX's components, and installed systems get it with \`bootc upgrade\`. To install AgentUX, use the newest ISOs, [$isos](https://github.com/$GH_REPO/releases/tag/$isos)'s, at \`$base/iso/stable/\`: they install $isos and then follow \`:stable\`, so the first \`bootc upgrade\` brings $tag.

## Images

This release's images are \`ghcr.io/agentux-os/agentux:$tag\` (KDE Plasma) and \`ghcr.io/agentux-os/agentux-cosmic:$tag\` (COSMIC), and each one's **stable** channel (\`:stable\`) now points at it. Installed systems follow \`:stable\` and update with \`bootc upgrade\`; to follow the nightly builds instead, \`sudo bootc switch ghcr.io/agentux-os/agentux:latest\` (\`agentux-cosmic:latest\` for COSMIC). See the [README](https://github.com/agentux-os/agentux-os#release-channels).
EOF
if gh release view "$tag" >/dev/null 2>&1; then
    gh release edit "$tag" "${pre[@]}" --verify-tag --title "AgentUX $tag" --notes-file notes.md
else
    gh release create "$tag" "${pre[@]}" --verify-tag --title "AgentUX $tag" --notes-file notes.md
fi
echo "release: $(gh release view "$tag" --json url --jq .url) (no ISOs; the newest are $isos's)" |
    tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"

# ---- releases.json ---------------------------------------------------------------

OWNER=${OWNER:-agentux-os} "$here/releases-json.sh" releases.json
sign releases.json
s3 cp releases.json "s3://$bucket/releases.json" --content-type application/json --cache-control "$short"
s3 cp releases.json.sigstore.json "s3://$bucket/releases.json.sigstore.json" \
    --content-type application/json --cache-control "$short"
echo "- [\`releases.json\`]($base/releases.json): $(jq -r '[.releases[].tag] | join(", ")' releases.json)" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
