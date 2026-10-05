#!/usr/bin/bash
# Checks the signature policy the image ships, with the image's own skopeo,
# /etc/containers/policy.json, registries.d and public key, i.e. exactly what
# an installed system uses for `bootc upgrade`:
#   tests/sigpolicy.sh <local image> <repository> <signed digest> <signed tag> <unsigned tag>
# Run on the CI host after the image was pushed and signed. A pull of the
# signed digest and tag must pass, a pull of an unsigned image in the same
# repository must be refused for lack of a signature, and an image from
# another registry must still pass (Fedora's defaults are kept).
# For a manifest list, ARCH (amd64, arm64) picks the image skopeo resolves
# it to, as a system of that architecture would (skopeo --override-arch); the
# signature checked is that image's.
# AUTHFILE: registry credentials (the repository may be private).
# WORKDIR: where the pulled copies go; needs room for the whole image.
set -euo pipefail

local_image="$1" repo="$2" digest="$3" tag="$4" unsigned_tag="$5"
authfile="${AUTHFILE:?}"
workdir="${WORKDIR:?}"
other=docker://quay.io/libpod/alpine:latest
arch_args=()
[[ -n "${ARCH:-}" ]] && arch_args=(--override-arch "$ARCH")

fail=0
in_image() {
    podman run --rm \
        -v "$authfile:/run/agentux-auth.json:ro" \
        -v "$workdir:/work" \
        "$local_image" "$@"
}
copy() {
    local src="$1" dest="$2"
    in_image skopeo "${arch_args[@]}" copy --quiet --authfile /run/agentux-auth.json "$src" "dir:/work/$dest" 2>&1
}

echo "::group::Shipped policy"
in_image jq '.transports.docker["ghcr.io/agentux-os/agentux"]' /etc/containers/policy.json
in_image cat /etc/containers/registries.d/agentux-os.yaml
in_image skopeo --version
echo "::endgroup::"

for ref in "$repo@$digest" "$repo:$tag"; do
    echo "::group::Signed: $ref${ARCH:+ (linux/$ARCH)}"
    if out="$(copy "docker://$ref" signed)"; then
        echo "accepted, as it should be"
    else
        echo "$out"
        echo "::error::the shipped policy rejects the signed image $ref"
        fail=1
    fi
    rm -rf "${workdir:?}/signed"
    echo "::endgroup::"
done

echo "::group::Unsigned: $repo:$unsigned_tag"
if out="$(copy "docker://$repo:$unsigned_tag" unsigned)"; then
    echo "::error::the shipped policy accepts the unsigned image $repo:$unsigned_tag"
    fail=1
elif grep -q 'A signature was required, but no signature exists' <<<"$out"; then
    echo "$out"
    echo "rejected for lack of a signature, as it should be"
else
    echo "$out"
    echo "::error::pulling $repo:$unsigned_tag failed, but not because of the signature policy"
    fail=1
fi
rm -rf "${workdir:?}/unsigned"
echo "::endgroup::"

echo "::group::Other registry: $other"
if out="$(copy "$other" other)"; then
    echo "accepted, as it should be"
else
    echo "$out"
    echo "::error::the shipped policy rejects $other; other registries must keep Fedora's defaults"
    fail=1
fi
rm -rf "${workdir:?}/other"
echo "::endgroup::"

exit "$fail"
