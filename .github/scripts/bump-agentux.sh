#!/usr/bin/env bash
set -euo pipefail

containerfile=${AGENTUX_CONTAINERFILE:-Containerfile}
[[ -f "$containerfile" ]] || { echo "Containerfile not found: $containerfile" >&2; exit 2; }
command -v gh >/dev/null || { echo 'gh is required (authenticate with `gh auth login`)' >&2; exit 2; }

latest() {
    local tag
    tag=$(gh release list --repo "agentux-os/$1" --exclude-drafts --limit 1 --json tagName --jq '.[0].tagName | ltrimstr("v")')
    [[ "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || { echo "no valid release found for agentux-os/$1: $tag" >&2; return 1; }
    printf '%s\n' "$tag"
}

core=$(latest agentux-core)
desktop=$(latest agentux-desktop)
core_assets=$(gh release view "v$core" --repo agentux-os/agentux-core --json assets --jq '.assets[].name')
desktop_assets=$(gh release view "v$desktop" --repo agentux-os/agentux-desktop --json assets --jq '.assets[].name')

required=()
for arch in x86_64 aarch64; do
    required+=("agentux-$core-1.fc44.$arch.rpm" "agentux-cockpit-$desktop-1.$arch.rpm")
done
for bundle in common plasma cosmic; do
    archive="agentux-desktop-$bundle-$desktop.tar.gz"
    required+=("$archive" "$archive.sha256")
done

missing=()
for asset in "${required[@]}"; do
    if [[ "$asset" == agentux-*-1.fc44.*.rpm ]]; then
        grep -qxF "$asset" <<<"$core_assets" || missing+=("agentux-core v$core: $asset")
    else
        grep -qxF "$asset" <<<"$desktop_assets" || missing+=("agentux-desktop v$desktop: $asset")
    fi
done
if ((${#missing[@]})); then
    printf 'missing release asset %s\n' "${missing[@]}" >&2
    exit 1
fi

checksum() {
    local archive=$1 sidecar output hash listed
    sidecar="$archive.sha256"
    output=$(gh release download "v$desktop" --repo agentux-os/agentux-desktop --pattern "$sidecar" --output -)
    read -r hash listed <<<"$output"
    listed=${listed#\*}
    [[ "$hash" =~ ^[a-f0-9]{64}$ && "$listed" == "$archive" ]] || { echo "invalid checksum sidecar $sidecar: $output" >&2; return 1; }
    printf '%s\n' "$hash"
}

common_sha=$(checksum "agentux-desktop-common-$desktop.tar.gz")
plasma_sha=$(checksum "agentux-desktop-plasma-$desktop.tar.gz")
cosmic_sha=$(checksum "agentux-desktop-cosmic-$desktop.tar.gz")

declare -A values=(
    [AGENTUX_CORE_VERSION]="$core"
    [AGENTUX_DESKTOP_VERSION]="$desktop"
    [AGENTUX_COMMON_SHA256]="$common_sha"
    [AGENTUX_PLASMA_SHA256]="$plasma_sha"
    [AGENTUX_COSMIC_SHA256]="$cosmic_sha"
)
for key in "${!values[@]}"; do
    count=$(grep -c "^ARG $key=" "$containerfile" || true)
    [[ "$count" == 1 ]] || { echo "$containerfile must define ARG $key exactly once (found $count)" >&2; exit 1; }
done

directory=$(dirname -- "$containerfile")
tmp=$(mktemp "$directory/.agentux-containerfile.XXXXXX")
trap 'rm -f "$tmp"' EXIT
sed \
    -e "s|^ARG AGENTUX_CORE_VERSION=.*|ARG AGENTUX_CORE_VERSION=$core|" \
    -e "s|^ARG AGENTUX_DESKTOP_VERSION=.*|ARG AGENTUX_DESKTOP_VERSION=$desktop|" \
    -e "s|^ARG AGENTUX_COMMON_SHA256=.*|ARG AGENTUX_COMMON_SHA256=$common_sha|" \
    -e "s|^ARG AGENTUX_PLASMA_SHA256=.*|ARG AGENTUX_PLASMA_SHA256=$plasma_sha|" \
    -e "s|^ARG AGENTUX_COSMIC_SHA256=.*|ARG AGENTUX_COSMIC_SHA256=$cosmic_sha|" \
    "$containerfile" > "$tmp"
for key in "${!values[@]}"; do
    grep -qx "ARG $key=${values[$key]}" "$tmp" || { echo "failed to update ARG $key" >&2; exit 1; }
done
chmod --reference="$containerfile" "$tmp"
mv -- "$tmp" "$containerfile"
trap - EXIT

echo "agentux-core $core, agentux-desktop $desktop (common/plasma/cosmic checksums verified)"
if [[ "$containerfile" == "Containerfile" ]]; then
    git diff --stat -- "$containerfile"
fi
