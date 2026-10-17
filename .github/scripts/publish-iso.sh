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
#            release is created with the checksums and the links, and
#            latest.json moves to the release. EXPECT lists the ISO names
#            (without .iso) the release must have; PLASMA_DIGEST and
#            HYPRLAND_DIGEST (optional) are the promoted images' digests,
#            for latest.json.
#
# Layout of the bucket:
#   iso/stable/<prefix>-<arch>.iso        the newest release
#   iso/<tag>/<prefix>-<tag>-<arch>.iso   every release, kept
#   iso/nightly/<prefix>-<arch>.iso       the newest weekly or dispatched build
#   latest.json                           the newest release, for the website
#   releases.json                         every release's image digests, for agentux-version
# each ISO with .iso.sha256 (naming the file next to it, so `sha256sum
# --check` works on either copy) and .iso.sha256.sigstore.json (a cosign
# bundle, signed with the AgentUX key that also signs the images). Every
# directory also has SHA256SUMS, all its ISOs' checksums in one file, and
# SHA256SUMS.sigstore.json; latest.json has latest.json.sigstore.json.
#
# SHA256SUMS is rebuilt from the .sha256 files in the bucket after every
# upload, not from this run's ISOs: the ISOs of one channel come from
# separate jobs and workflows (iso.yml, live.yml), and each of them leaves a
# complete file behind.
#
# GitHub release assets are limited to 2 GiB, which every ISO exceeds, so a
# release carries the checksums, their signatures and the download links.
#
# Environment: R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY,
# COSIGN_PRIVATE_KEY, COSIGN_PASSWORD; GH_TOKEN for a release.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd) # the script cds into DIR below
# gh works from DIR, which is not a git checkout: name the repository.
export GH_REPO=${GH_REPO:-${GITHUB_REPOSITORY:-agentux-os/agentux-os}}
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
# --only-show-errors is an option of cp, not of ls (which rejects it).
s3() {
    local quiet=(--only-show-errors)
    [[ $1 == ls ]] && quiet=()
    aws s3 --endpoint-url "https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com" "${quiet[@]}" "$@"
}
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

# ---- SHA256SUMS ----------------------------------------------------------------

# sums DIR: rebuilds DIR/SHA256SUMS from the .iso.sha256 files in DIR, signs
# it and uploads both.
sums() {
    local d=$1 work f
    work=$(mktemp -d)
    s3 ls "s3://$bucket/$d/" | awk '{print $4}' | grep '\.iso\.sha256$' | sort >"$work/list" || true
    if [[ ! -s $work/list ]]; then
        echo "::error::no checksums in $d/"
        return 1
    fi
    : >"$work/SHA256SUMS"
    while read -r f; do
        s3 cp "s3://$bucket/$d/$f" "$work/$f"
        # One line, "<sha256>  <file>.iso", naming a file in this directory.
        if ! grep -Eq '^[0-9a-f]{64}  [^/ ]+\.iso$' "$work/$f" || [[ $(wc -l <"$work/$f") != 1 ]]; then
            echo "::error::$d/$f is not a single sha256sum line"
            return 1
        fi
        cat "$work/$f" >>"$work/SHA256SUMS"
    done <"$work/list"
    sign "$work/SHA256SUMS"
    s3 cp "$work/SHA256SUMS" "s3://$bucket/$d/SHA256SUMS" --content-type text/plain --cache-control "$short"
    s3 cp "$work/SHA256SUMS.sigstore.json" "s3://$bucket/$d/SHA256SUMS.sigstore.json" \
        --content-type application/json --cache-control "$short"
    echo "$d/SHA256SUMS: $(wc -l <"$work/SHA256SUMS") ISOs"
    echo "- [\`$d/SHA256SUMS\`]($base/$d/SHA256SUMS)" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
    [[ $d == "$versioned" ]] && cp "$work/SHA256SUMS" "$work/SHA256SUMS.sigstore.json" "$dir/"
    rm -rf "$work"
}
if [[ -n $versioned ]]; then sums "$versioned"; fi
sums "$channel"

# The directory pages (R2 lists nothing by itself).
"$here/download-index.sh"

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

| Variant / ISO | x86_64 | aarch64 |
|---|---|---|
| **Plasma Live**: try AgentUX without installing, then install it (needs internet) | $(link "agentux-live-$tag-x86_64") | $(link "agentux-live-$tag-aarch64") |
| **Plasma Installer**: offline install | $(link "agentux-$tag-x86_64") | $(link "agentux-$tag-aarch64") |
| **Hyprland Live**: try AgentUX without installing, then install it (needs internet) | $(link "agentux-hyprland-live-$tag-x86_64") | $(link "agentux-hyprland-live-$tag-aarch64") |
| **Hyprland Installer**: offline install | $(link "agentux-hyprland-$tag-x86_64") | $(link "agentux-hyprland-$tag-aarch64") |

The x86_64 ISOs were booted and their installed systems checked in a VM before this release was published: live ISOs from their live sessions and installer ISOs unattended. The aarch64 ISOs are built natively but not boot-tested: GitHub's arm64 runners have no KVM.

The newest release's ISOs are always at \`$base/iso/stable/\`: \`agentux-live\`, \`agentux\`, \`agentux-hyprland-live\`, and \`agentux-hyprland\`, each with \`x86_64\` and \`aarch64\` variants.

Verify a download:

\`\`\`sh
sha256sum --check agentux-live-$tag-x86_64.iso.sha256
cosign verify-blob --key https://raw.githubusercontent.com/agentux-os/agentux-os/main/files/etc/pki/containers/agentux-os.pub \\
  --bundle agentux-live-$tag-x86_64.iso.sha256.sigstore.json agentux-live-$tag-x86_64.iso.sha256
\`\`\`

## Images

This release's images are \`ghcr.io/agentux-os/agentux:$tag\` and \`ghcr.io/agentux-os/agentux-hyprland:$tag\`, and the **stable** channel (\`:stable\`) now points at them. Systems installed from these ISOs follow \`:stable\` and update with \`bootc upgrade\`; to follow the nightly builds instead, \`sudo bootc switch ghcr.io/agentux-os/agentux:latest\`. See the [README](https://github.com/agentux-os/agentux-os#release-channels).
EOF
if gh release view "$tag" >/dev/null 2>&1; then
    gh release edit "$tag" "${pre[@]}" --verify-tag --title "AgentUX $tag" --notes-file "$notes"
else
    gh release create "$tag" "${pre[@]}" --verify-tag --title "AgentUX $tag" --notes-file "$notes"
fi
assets=(SHA256SUMS SHA256SUMS.sigstore.json)
for name in "${published[@]}"; do assets+=("$name.iso.sha256" "$name.iso.sha256.sigstore.json"); done
gh release upload "$tag" --clobber "${assets[@]}"
release_url=$(gh release view "$tag" --json url --jq .url)
echo "release: $release_url" | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"

# ---- latest.json -----------------------------------------------------------------

# The website's download buttons read https://download.agentuxos.org/latest.json.
# Written last, once everything it links to is in place.
isos_json=$(
    for name in "${published[@]}"; do
        arch=${name##*-}
        kind=installer; [[ $name == *-live-* ]] && kind=live
        variant=plasma; [[ $name == agentux-hyprland-* ]] && variant=hyprland
        alias=${name%-"$tag"-"$arch"}-$arch
        jq -n --arg name "$name.iso" --arg url "$base/$versioned/$name.iso" \
            --arg stable_url "$base/$channel/$alias.iso" \
            --argjson size "$(stat -c %s "$name.iso")" \
            --arg sha256 "$(cut -d' ' -f1 "$name.iso.sha256")" \
            --arg arch "$arch" --arg kind "$kind" --arg variant "$variant" \
            --argjson tested "$([[ $arch == x86_64 ]] && echo true || echo false)" \
            '{name: $name, url: $url, stable_url: $stable_url, size: $size, sha256: $sha256,
              arch: $arch, kind: $kind, variant: $variant, channel: "stable", boot_tested: $tested}'
    done | jq -s 'sort_by(.kind != "live", .arch != "x86_64")'
)
jq -n --arg version "$tag" --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg release "$release_url" --arg sums "$base/$versioned/SHA256SUMS" \
    --arg key "https://raw.githubusercontent.com/agentux-os/agentux-os/main/files/etc/pki/containers/agentux-os.pub" \
    --arg plasma "${PLASMA_DIGEST:-}" --arg hyprland "${HYPRLAND_DIGEST:-}" \
    --argjson isos "$isos_json" \
    '{version: $version, date: $date, channel: "stable", release_notes: $release,
      sha256sums: $sums, sha256sums_signature: ($sums + ".sigstore.json"), public_key: $key,
      images: {
        plasma: ({ref: ("ghcr.io/agentux-os/agentux:" + $version), channel: "ghcr.io/agentux-os/agentux:stable"}
                 + (if $plasma != "" then {digest: $plasma} else {} end)),
        hyprland: ({ref: ("ghcr.io/agentux-os/agentux-hyprland:" + $version), channel: "ghcr.io/agentux-os/agentux-hyprland:stable"}
                   + (if $hyprland != "" then {digest: $hyprland} else {} end))
      },
      isos: $isos}' >latest.json
cat latest.json
sign latest.json
s3 cp latest.json "s3://$bucket/latest.json" --content-type application/json --cache-control "$short"
s3 cp latest.json.sigstore.json "s3://$bucket/latest.json.sigstore.json" \
    --content-type application/json --cache-control "$short"
echo "- [\`latest.json\`]($base/latest.json) now names $tag" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"

# ---- releases.json ---------------------------------------------------------------

# Every release's image digests, so installed systems can name the release
# they run (agentux-version; ADR 0012). Rebuilt from the registry's v* tags,
# which the release job has just moved for this one.
OWNER=${OWNER:-agentux-os} "$here/releases-json.sh" releases.json
sign releases.json
s3 cp releases.json "s3://$bucket/releases.json" --content-type application/json --cache-control "$short"
s3 cp releases.json.sigstore.json "s3://$bucket/releases.json.sigstore.json" \
    --content-type application/json --cache-control "$short"
echo "- [\`releases.json\`]($base/releases.json): $(jq -r '[.releases[].tag] | join(", ")' releases.json)" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"

# Again, so / lists latest.json from the first release on.
"$here/download-index.sh"
