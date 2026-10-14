#!/usr/bin/env bash
# Publishes ISOs on download.agentuxos.org (the Cloudflare R2 bucket
# agentux-downloads).
#
# usage: publish-iso.sh nightly|release DIR
#   DIR holds the ISOs to publish, each <name>.iso with its <name>.iso.sha256,
#   as the ISO jobs uploaded them (<prefix>-<version>-<arch>, e.g.
#   agentux-live-v0.5.0-x86_64 or agentux-20261014-x86_64).
#
#   nightly  the weekly build or a dispatch with publish set (iso.yml,
#            live.yml): each ISO replaces its channel copy in iso/nightly/
#            under its name without the date (agentux-live-x86_64.iso).
#   release  a v* tag, from release.yml once the owner approved it: each ISO
#            goes to iso/<tag>/ under its own name, and its copy replaces the
#            one in iso/stable/ (agentux-live-x86_64.iso); then the GitHub
#            release is created with the checksums and the links. EXPECT
#            lists the ISO names (without .iso) the release must have.
#
# Layout of the bucket:
#   iso/stable/<prefix>-<arch>.iso        the newest release
#   iso/<tag>/<prefix>-<tag>-<arch>.iso   every release, kept
#   iso/nightly/<prefix>-<arch>.iso       the newest weekly or dispatched build
# each with .iso.sha256 (naming the file next to it, so `sha256sum --check`
# works on either copy) and .iso.sha256.sigstore.json (a cosign bundle, signed
# with the AgentUX key that also signs the images).
#
# GitHub release assets are limited to 2 GiB, which every ISO exceeds, so a
# release carries the checksums, their signatures and the download links.
#
# Environment: R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY,
# COSIGN_PRIVATE_KEY, COSIGN_PASSWORD; GH_TOKEN for a release.
set -euo pipefail

mode=${1:?usage: publish-iso.sh nightly|release DIR}
dir=$(cd "${2:?usage: publish-iso.sh nightly|release DIR}" && pwd)
bucket=agentux-downloads
base=https://download.agentuxos.org

for v in R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY COSIGN_PRIVATE_KEY; do
    if [[ -z ${!v:-} ]]; then
        echo "::error::$v is not set; cannot publish (the secrets live in the nightly and release environments)"
        exit 1
    fi
done

case "$mode" in
    release)
        if [[ ${GITHUB_REF:-} != refs/tags/v* ]]; then
            echo "::error::release mode needs a v* tag (GITHUB_REF=${GITHUB_REF:-})"
            exit 1
        fi
        tag=$GITHUB_REF_NAME
        versioned="iso/$tag"
        channel=iso/stable
        ;;
    nightly)
        tag="" versioned=""
        channel=iso/nightly
        ;;
    *) echo "unknown mode $mode" >&2; exit 2 ;;
esac

command -v aws >/dev/null || sudo snap install aws-cli --classic
export AWS_ACCESS_KEY_ID=$R2_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$R2_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION=auto
# R2 does not support the newer default checksum headers of the AWS CLI.
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
s3() { aws s3 --endpoint-url "https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com" --only-show-errors "$@"; }
# Files that are replaced (channel copies) are cached briefly; the ISOs
# themselves are too large for Cloudflare's cache anyway.
short="public, max-age=300"
long="public, max-age=86400"

sign() { cosign sign-blob --yes --key env://COSIGN_PRIVATE_KEY --bundle "$1.sigstore.json" "$1" >/dev/null; }

shopt -s nullglob
isos=("$dir"/*.iso)
if (( ${#isos[@]} == 0 )); then
    echo "::error::no ISOs in $dir"
    exit 1
fi
if [[ $mode == release ]]; then
    for want in ${EXPECT:?release mode needs EXPECT}; do
        if [[ ! -f $dir/$want.iso ]]; then
            echo "::error::the release has no $want.iso"
            exit 1
        fi
    done
fi

cd "$dir"
published=()
for iso in "${isos[@]}"; do
    name=$(basename "$iso" .iso)
    arch=${name##*-}
    case "$arch" in x86_64 | aarch64) ;; *) echo "::error::$name.iso: unknown architecture"; exit 1 ;; esac
    # The artifact is the file the ISO job tested; make sure it still is.
    sha256sum --check --strict "$name.iso.sha256"
    if [[ $mode == release ]]; then
        alias=${name%-"$tag"-"$arch"}-$arch
    else
        alias=$(sed -E 's/-[0-9]{8}-(x86_64|aarch64)$/-\1/' <<<"$name")
    fi
    if [[ $alias == "$name" || $alias == -* ]]; then
        echo "::error::$name.iso is not named <prefix>-<version>-<arch>"
        exit 1
    fi

    # The channel copy's checksum file names the channel copy.
    sed "s/  $name\.iso\$/  $alias.iso/" "$name.iso.sha256" >"$alias.iso.sha256.channel"
    grep -q "  $alias.iso\$" "$alias.iso.sha256.channel"

    if [[ -n $versioned ]]; then
        sign "$name.iso.sha256"
        s3 cp "$name.iso" "s3://$bucket/$versioned/$name.iso" \
            --content-type application/x-iso9660-image --cache-control "$long"
        for f in "$name.iso.sha256" "$name.iso.sha256.sigstore.json"; do
            s3 cp "$f" "s3://$bucket/$versioned/$f" --content-type text/plain --cache-control "$long"
        done
        # Server-side copy (multipart for files over 5 GB), no second upload.
        s3 cp "s3://$bucket/$versioned/$name.iso" "s3://$bucket/$channel/$alias.iso" \
            --content-type application/x-iso9660-image --cache-control "$short" \
            --metadata-directive REPLACE --metadata "build=$name"
    else
        s3 cp "$name.iso" "s3://$bucket/$channel/$alias.iso" \
            --content-type application/x-iso9660-image --cache-control "$short" --metadata "build=$name"
    fi
    mv "$alias.iso.sha256.channel" "$alias.iso.sha256"
    sign "$alias.iso.sha256"
    for f in "$alias.iso.sha256" "$alias.iso.sha256.sigstore.json"; do
        s3 cp "$f" "s3://$bucket/$channel/$f" --content-type text/plain --cache-control "$short"
    done

    size=$(du -h "$name.iso" | cut -f1)
    {
        if [[ -n $versioned ]]; then
            echo "- \`$name.iso\` ($size): $base/$versioned/$name.iso, and $base/$channel/$alias.iso"
        else
            echo "- \`$name.iso\` ($size): $base/$channel/$alias.iso"
        fi
    } >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
    echo "published $name.iso as $base/$channel/$alias.iso"
    published+=("$name")
done

[[ $mode == release ]] || exit 0

# ---- the GitHub release ------------------------------------------------------

link() { echo "[$1.iso]($base/$versioned/$1.iso)"; }
pre=()
# Pre-releases while AgentUX is pre-1.0.
[[ $tag == v0.* ]] && pre=(--prerelease)
notes=$(mktemp)
cat >"$notes" <<EOF
AgentUX $tag.

## Downloads

ISOs are hosted on download.agentuxos.org (GitHub limits release files to 2 GiB). Each has a \`.sha256\` checksum, attached here and next to the ISO, signed with the AgentUX key.

| | x86_64 | aarch64 |
|---|---|---|
| **Live ISO**: try AgentUX without installing, then install it (needs internet) | $(link "agentux-live-$tag-x86_64") | $(link "agentux-live-$tag-aarch64") |
| **Installer ISO**: offline install | $(link "agentux-$tag-x86_64") | $(link "agentux-$tag-aarch64") |

The x86_64 live ISO was booted in a VM and installed from its live session before this release was published, and the installed system checked. The installer ISOs and the aarch64 live ISO are built natively but not boot-tested (GitHub's arm64 runners have no KVM).

The newest release's ISOs are always at \`$base/iso/stable/\` (\`agentux-live-x86_64.iso\`, \`agentux-x86_64.iso\`, and the \`aarch64\` ones).

Verify a download:

\`\`\`sh
sha256sum --check agentux-live-$tag-x86_64.iso.sha256
cosign verify-blob --key https://raw.githubusercontent.com/agentux-os/agentux-os/main/files/etc/pki/containers/agentux-os.pub \\
  --bundle agentux-live-$tag-x86_64.iso.sha256.sigstore.json agentux-live-$tag-x86_64.iso.sha256
\`\`\`

## Images

This release's images are \`ghcr.io/agentux-os/agentux:$tag\` and \`ghcr.io/agentux-os/agentux-hyprland:$tag\`, and the **stable** channel (\`:stable\`) now points at them. Systems installed from these ISOs follow \`:stable\` and update with \`bootc upgrade\`; to follow the nightly builds instead, \`sudo bootc switch ghcr.io/agentux-os/agentux:latest\`. See the [README](https://github.com/agentux-os/agentux-os#release-channels).
EOF
gh release view "$tag" >/dev/null 2>&1 \
    || gh release create "$tag" "${pre[@]}" --verify-tag --title "AgentUX $tag" --notes-file "$notes"
assets=()
for name in "${published[@]}"; do assets+=("$name.iso.sha256" "$name.iso.sha256.sigstore.json"); done
gh release upload "$tag" --clobber "${assets[@]}"
echo "release: $(gh release view "$tag" --json url --jq .url)" | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
