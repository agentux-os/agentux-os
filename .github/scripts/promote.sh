#!/usr/bin/env bash
# Promotes a release's image: points tags at a digest that build.yml already
# built, smoke-tested, signed and checked against the shipped policy.
#
# usage: promote.sh REPOSITORY DIGEST TAG...
#   e.g. promote.sh ghcr.io/agentux-os/agentux sha256:... v0.5.0 stable
#
# A promotion copies the manifest list as it is (skopeo --all
# --preserve-digests), so the digest does not change and the signatures,
# which cosign stores by digest (the sha256-<digest>.sig tag), cover the new
# tags too. After each copy the tag must resolve to exactly DIGEST, and the
# AgentUX key and the keyless signature of build.yml at this ref must verify
# on the tag, the list and each architecture's image (what an installed
# system checks).
#
# Needs skopeo, cosign, jq, and a docker/podman login to ghcr.io.
set -euo pipefail

repo=${1:?usage: promote.sh REPOSITORY DIGEST TAG...}
digest=${2:?usage: promote.sh REPOSITORY DIGEST TAG...}
shift 2
(( $# > 0 )) || { echo "usage: promote.sh REPOSITORY DIGEST TAG..." >&2; exit 2; }
[[ $digest =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "::error::not a digest: $digest"; exit 1; }
key=files/etc/pki/containers/agentux-os.pub
identity="https://github.com/${GITHUB_REPOSITORY:?}/.github/workflows/build.yml@${GITHUB_REF:?}"

verify() {
    cosign verify --key "$key" "$1" >/dev/null
    cosign verify "$1" --certificate-identity "$identity" \
        --certificate-oidc-issuer https://token.actions.githubusercontent.com >/dev/null
    echo "$1: AgentUX key and keyless ($identity) signatures verified"
}

raw=$(skopeo inspect --raw "docker://$repo@$digest")
mapfile -t images < <(jq -r '.manifests[].digest' <<<"$raw")
(( ${#images[@]} == 2 )) || { echo "::error::$repo@$digest is not a two-architecture list"; exit 1; }
for d in "$digest" "${images[@]}"; do verify "$repo@$d"; done

for tag in "$@"; do
    skopeo copy --quiet --all --preserve-digests "docker://$repo@$digest" "docker://$repo:$tag"
    # ghcr.io can answer "manifest unknown" for a moment after the copy.
    for i in 1 2 3 4 5 6; do
        got="sha256:$(skopeo inspect --raw "docker://$repo:$tag" | sha256sum | cut -d' ' -f1)"
        [[ $got == "$digest" ]] && break
        sleep $((i * 5))
    done
    if [[ $got != "$digest" ]]; then
        echo "::error::$repo:$tag resolves to $got, not $digest"
        exit 1
    fi
    verify "$repo:$tag"
    echo "$repo:$tag -> $digest"
    echo "- \`$repo:$tag\` → \`$digest\`" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
done
