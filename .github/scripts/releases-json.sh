#!/usr/bin/env bash
# Writes releases.json: every AgentUX release with the images it promoted,
# so an installed system can name the release it runs (agentux-version looks
# its booted digest up in it; ADR 0012 in agentux-os/agentux). A release
# promotes an image built earlier, so the image itself cannot carry its
# release name; this file maps the digests back to the tags.
#
# usage: releases-json.sh OUT
#
# Rebuilt from the registry each time, not appended to: the releases are the
# v* tags of ghcr.io/<owner>/agentux (only an approved release moves one,
# see release.yml), newest first, each with both variants' manifest-list
# digest, each architecture's image digest (what bootc and rpm-ostree report
# on a booted system) and the image's version label. So a release that
# predates this file is listed too, and nothing drifts from what is
# published. publish-iso.sh signs and uploads it after every release.
#
#   {"schema": 1, "updated": "<UTC>", "releases": [
#     {"tag": "v0.5.3", "images": {
#       "plasma": {"repository": "ghcr.io/agentux-os/agentux",
#                  "digest": "sha256:<list>",
#                  "manifests": {"amd64": "sha256:...", "arm64": "sha256:..."},
#                  "image_version": "2026.10.15.063578e", "created": "<UTC>"},
#       "hyprland": {...}}}, ...]}
#
# Needs skopeo and jq. OWNER (default agentux-os) names the organisation.
set -euo pipefail

out=${1:?usage: releases-json.sh OUT}
owner=${OWNER:-agentux-os}

inspect_raw() {
    # ghcr.io can answer "manifest unknown" for a moment after a promotion.
    local i
    for i in 1 2 3 4; do
        skopeo inspect --raw "docker://$1" 2>/dev/null && return 0
        sleep $((i * 5))
    done
    return 1
}

mapfile -t tags < <(
    skopeo list-tags "docker://ghcr.io/$owner/agentux" \
        | jq -r '.Tags[] | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+([-.+][0-9A-Za-z.-]+)?$"))' \
        | sort -rV
)
# No release yet (the first one, or after the old ones were removed): an
# empty list. A release always has its own tag here, as publish-iso.sh runs
# this after the promotion.
if (( ${#tags[@]} == 0 )); then
    echo "::notice::no v* tags in ghcr.io/$owner/agentux yet; writing an empty release list"
    jq -n --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{schema: 1, updated: $date, releases: []}' >"$out"
    exit 0
fi

for tag in "${tags[@]}"; do
    images='{}'
    pairs=(plasma=agentux)
    # COSMIC is released after v0.5.9, when Hyprland left.
    [[ $tag != v0.5.9 && $(printf '%s\n' "$tag" v0.5.9 | sort -V | head -n1) == v0.5.9 ]] && pairs+=(cosmic=agentux-cosmic)
    # Hyprland shipped up to v0.5.9; older releases keep listing it, so the
    # systems still on it can name their version.
    [[ $(printf '%s\n' "$tag" v0.5.9 | sort -V | head -n1) == "$tag" ]] && pairs+=(hyprland=agentux-hyprland)
    for pair in "${pairs[@]}"; do
        variant=${pair%%=*}
        repo="ghcr.io/$owner/${pair#*=}"
        if ! raw=$(inspect_raw "$repo:$tag"); then
            echo "$repo:$tag: not found, skipped" >&2
            continue
        fi
        digest="sha256:$(printf '%s' "$raw" | sha256sum | cut -d' ' -f1)"
        manifests=$(jq -c '[.manifests[]? | select(.platform.os == "linux") | {(.platform.architecture): .digest}] | add // {}' <<<"$raw")
        config=$(skopeo inspect --override-os linux --override-arch amd64 "docker://$repo@$digest" \
            | jq -c '{created: .Created, version: (.Labels["org.opencontainers.image.version"] // "")}')
        images=$(jq -c --arg k "$variant" --arg repo "$repo" --arg d "$digest" \
            --argjson m "$manifests" --argjson c "$config" \
            '. + {($k): {repository: $repo, digest: $d, manifests: $m,
                         image_version: (if $c.version == "" then null else $c.version end),
                         created: $c.created}}' <<<"$images")
    done
    jq -n --arg tag "$tag" --argjson images "$images" '{tag: $tag, images: $images}'
    echo "$tag: $(jq -r '[.[] | .digest] | join(", ")' <<<"$images")" >&2
done | jq -s --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{schema: 1, updated: $date, releases: .}' >"$out"

jq -e '.schema == 1 and (.releases | length > 0) and all(.releases[]; .images.plasma.digest | startswith("sha256:"))' \
    "$out" >/dev/null
echo "$out: $(jq '.releases | length' "$out") releases"
