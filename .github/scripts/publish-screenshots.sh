#!/usr/bin/env bash
# Publishes the release's screenshots on download.agentuxos.org
# (agentux-os#73): the showcase shots the live ISO tests took
# (tests/live-vm.sh), one artifact per desktop as release.yml downloads them,
#
#   DIR/showcase-<desktop>-<run>/showcase-<shot>.png
#
# as WebP at
#
#   screenshots/<tag>/<desktop>-<shot>.webp     (kept, cached for long)
#   screenshots/stable/<desktop>-<shot>.webp    (the newest release, short cache)
#
# with screenshots/stable/index.json listing them, so the README and the site
# link fixed URLs that follow every release.
#
#   .github/scripts/publish-screenshots.sh DIR
#
# Environment: R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY; a v* tag
# (GITHUB_REF_NAME).
set -euo pipefail

dir=${1:?usage: publish-screenshots.sh DIR}
bucket=agentux-downloads
base=https://download.agentuxos.org
tag=${GITHUB_REF_NAME:?a release tag is needed}
[[ $tag == v* ]] || { echo "::error::screenshots are published for v* tags, not $tag"; exit 1; }
for v in R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY; do
    [[ -n ${!v:-} ]] || { echo "::error::$v is not set"; exit 1; }
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
command -v cwebp >/dev/null || { sudo apt-get update -q && sudo apt-get install -y -q --no-install-recommends webp; } >/dev/null
shopt -s nullglob
names=()
for png in "$dir"/showcase-*/showcase-*.png; do
    desktop=$(basename "$(dirname "$png")")
    desktop=${desktop#showcase-}
    desktop=${desktop%-*}
    shot=$(basename "$png" .png)
    name="$desktop-${shot#showcase-}.webp"
    cwebp -quiet -q 85 "$png" -o "$work/$name"
    names+=("$name")
done
if (( ${#names[@]} == 0 )); then
    echo "::warning::no screenshots in $dir; the live tests took none"
    exit 0
fi

command -v aws >/dev/null || sudo snap install aws-cli --classic
export AWS_ACCESS_KEY_ID=$R2_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$R2_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION=auto
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
endpoint="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
s3() { aws s3 --endpoint-url "$endpoint" --only-show-errors "$@"; }

long="public, max-age=31536000, immutable"
short="public, max-age=300"
for name in "${names[@]}"; do
    s3 cp "$work/$name" "s3://$bucket/screenshots/$tag/$name" --content-type image/webp --cache-control "$long"
    s3 cp "$work/$name" "s3://$bucket/screenshots/stable/$name" --content-type image/webp --cache-control "$short"
    echo "- [$name]($base/screenshots/stable/$name)" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
done
printf '%s\n' "${names[@]}" | jq -R . | jq -s --arg tag "$tag" --arg base "$base/screenshots/$tag" \
    '{release: $tag, screenshots: map({name: ., url: "\($base)/\(.)"})}' >"$work/index.json"
s3 cp "$work/index.json" "s3://$bucket/screenshots/stable/index.json" \
    --content-type application/json --cache-control "$short"
echo "published ${#names[@]} screenshots for $tag"
