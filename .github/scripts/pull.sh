#!/usr/bin/bash
# Pulls container images into the calling user's podman storage, retrying
# with backoff. quay.io's CDN often drops a blob download halfway through
# ("writing blob: ... unexpected EOF"), and podman's own retries (3, a few
# seconds apart) give up before it recovers; one such hiccup used to fail a
# whole image build. CI pulls the base image with this before `podman build`,
# which then uses the local copy (its default pull policy is "missing").
#
#   .github/scripts/pull.sh [IMAGE...]
#
# Without arguments, pulls the Containerfile's BASE_IMAGE default, expanded
# with FEDORA_VERSION. Pass explicit image references to pull other bases.
# Run it with sudo to pull into root's storage.
# PULL_ATTEMPTS (default 5) bounds the outer attempts; attempt n waits n*20 s.
set -euo pipefail

attempts="${PULL_ATTEMPTS:-5}"
images=("$@")
if (( ${#images[@]} == 0 )); then
    here="$(cd "$(dirname "$0")/../.." && pwd)"
    version="$(sed -n 's/^ARG FEDORA_VERSION=//p' "$here/Containerfile")"
    base="$(sed -n 's/^ARG BASE_IMAGE=//p' "$here/Containerfile")"
    base="${base//\$\{FEDORA_VERSION\}/$version}"
    if [[ -z "$version" || -z "$base" || "$base" == *'$'* ]]; then
        echo "cannot work out the base image from the Containerfile (BASE_IMAGE $base, FEDORA_VERSION $version)" >&2
        exit 1
    fi
    images=("$base")
fi

# Podman 5 can retry a failed pull itself, after a delay of our choosing;
# older ones (Ubuntu 24.04 ships 4.9) only have the outer loop below.
retry=()
if podman pull --help 2>/dev/null | grep -q -- '--retry-delay'; then
    retry=(--retry 3 --retry-delay 10s)
fi

for image in "${images[@]}"; do
    for (( i = 1; ; i++ )); do
        if podman pull "${retry[@]}" "$image"; then
            break
        fi
        if (( i >= attempts )); then
            echo "::error::pulling $image failed $attempts times"
            exit 1
        fi
        delay=$(( i * 20 ))
        echo "::warning::pulling $image failed (attempt $i of $attempts); retrying in ${delay}s"
        sleep "$delay"
    done
done
