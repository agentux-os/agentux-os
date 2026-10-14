#!/usr/bin/env bash
# Publishes an ISO on download.agentuxos.org (the Cloudflare R2 bucket
# agentux-downloads) and, for a v* tag, on the GitHub release.
#
# usage: publish-iso.sh <name> <latest>
#   <name>    the ISO's base name in the working directory: <name>.iso and
#             <name>.iso.sha256 (e.g. agentux-live-v0.5.0-x86_64)
#   <latest>  its stable name under iso/latest/ (e.g. agentux-live-x86_64)
#
# Layout of the bucket:
#   iso/<version>/<name>.iso                   tag builds (version = the tag)
#   iso/builds/<name>.iso                      scheduled and dispatched builds
#   iso/latest/<latest>.iso                    the newest published build
# each with .iso.sha256 and .iso.sha256.sigstore.json (cosign bundle, signed
# with the AgentUX key that also signs the images).
#
# GitHub release assets are limited to 2 GiB, which every ISO exceeds, so a
# release carries the checksums, their signatures and the download links.
#
# Environment: R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY,
# COSIGN_PRIVATE_KEY, COSIGN_PASSWORD; GH_TOKEN for a tag.
set -euo pipefail

name=$1
latest=$2
bucket=agentux-downloads
base=https://download.agentuxos.org

for v in R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY COSIGN_PRIVATE_KEY; do
    if [[ -z ${!v:-} ]]; then
        echo "::error::$v is not set; cannot publish $name.iso"
        exit 1
    fi
done
test -f "$name.iso" && test -f "$name.iso.sha256"

export AWS_ACCESS_KEY_ID=$R2_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$R2_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION=auto
# R2 does not support the newer default checksum headers of the AWS CLI.
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
s3() { aws s3 --endpoint-url "https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com" --only-show-errors "$@"; }

if [[ ${GITHUB_REF:-} == refs/tags/v* ]]; then
    dir="iso/${GITHUB_REF_NAME}"
else
    dir="iso/builds"
fi

sign() { cosign sign-blob --yes --key env://COSIGN_PRIVATE_KEY --bundle "$1.sigstore.json" "$1" >/dev/null; }

# The stable copy's checksum file names the stable file, so
# `sha256sum --check` works on either download.
sed "s/  $name\.iso\$/  $latest.iso/" "$name.iso.sha256" > "$latest.iso.sha256"
grep -q "  $latest.iso\$" "$latest.iso.sha256"
sign "$name.iso.sha256"
sign "$latest.iso.sha256"

s3 cp "$name.iso" "s3://$bucket/$dir/$name.iso" --content-type application/x-iso9660-image
for f in "$name.iso.sha256" "$name.iso.sha256.sigstore.json"; do
    s3 cp "$f" "s3://$bucket/$dir/$f" --content-type text/plain
done
# Server-side copy (multipart for files over 5 GB), no second upload.
s3 cp "s3://$bucket/$dir/$name.iso" "s3://$bucket/iso/latest/$latest.iso" \
    --content-type application/x-iso9660-image
for f in "$latest.iso.sha256" "$latest.iso.sha256.sigstore.json"; do
    s3 cp "$f" "s3://$bucket/iso/latest/$f" --content-type text/plain
done

url="$base/$dir/$name.iso"
size=$(du -h "$name.iso" | cut -f1)
{
    echo "Published \`$name.iso\` ($size): $url"
    echo "Latest: $base/iso/latest/$latest.iso"
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
echo "published $url"

[[ ${GITHUB_REF:-} == refs/tags/v* ]] || exit 0

# The release: created by whichever ISO job gets there first, with the
# notes listing every download; each job then attaches its own checksum and
# signature (the notes link them).
tag=$GITHUB_REF_NAME
notes=$(mktemp)
cat > "$notes" <<EOF
AgentUX $tag, a pre-release.

## Downloads

ISOs are hosted on download.agentuxos.org (GitHub limits release files to 2 GiB). Each has a \`.sha256\` checksum, attached here and next to the ISO, signed with the AgentUX key.

| | x86_64 | aarch64 |
|---|---|---|
| **Live ISO**: try AgentUX without installing, then install it (needs internet) | [agentux-live-$tag-x86_64.iso]($base/iso/$tag/agentux-live-$tag-x86_64.iso) | [agentux-live-$tag-aarch64.iso]($base/iso/$tag/agentux-live-$tag-aarch64.iso) (not boot-tested) |
| **Installer ISO**: offline install | [agentux-$tag-x86_64.iso]($base/iso/$tag/agentux-$tag-x86_64.iso) | [agentux-$tag-aarch64.iso]($base/iso/$tag/agentux-$tag-aarch64.iso) |

The newest ISOs are always at \`$base/iso/latest/\` (\`agentux-live-x86_64.iso\`, \`agentux-x86_64.iso\`, and the \`aarch64\` ones).

Verify a download:

\`\`\`sh
sha256sum --check agentux-live-$tag-x86_64.iso.sha256
cosign verify-blob --key https://raw.githubusercontent.com/agentux-os/agentux-os/main/files/etc/pki/containers/agentux-os.pub \\
  --bundle agentux-live-$tag-x86_64.iso.sha256.sigstore.json agentux-live-$tag-x86_64.iso.sha256
\`\`\`

Installed systems track \`ghcr.io/agentux-os/agentux:latest\` and update with \`bootc upgrade\`; see the [README](https://github.com/agentux-os/agentux-os#install).
EOF
gh release view "$tag" >/dev/null 2>&1 \
    || gh release create "$tag" --prerelease --title "AgentUX $tag" --notes-file "$notes" \
    || gh release view "$tag" >/dev/null
gh release upload "$tag" --clobber "$name.iso.sha256" "$name.iso.sha256.sigstore.json"
