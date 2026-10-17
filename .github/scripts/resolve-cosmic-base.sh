#!/usr/bin/env bash
set -euo pipefail

arch="${1:?usage: resolve-cosmic-base.sh amd64|arm64}"
case "$arch" in
  amd64|arm64) ;;
  *) echo "unsupported COSMIC base architecture: $arch" >&2; exit 2 ;;
esac

# Fedora's community-built COSMIC Atomic images are published with a short
# Quay retention window. Resolve the nightly channel at build time, then use
# only its immutable platform digest for pull/build and record it in CI.
repository=quay.io/fedora-ostree-desktops/cosmic-atomic
tag=44
raw="$(skopeo inspect --raw "docker://${repository}:${tag}")"
digest="$(jq -er --arg arch "$arch" '
  [.manifests[] | select(.platform.os == "linux" and .platform.architecture == $arch)]
  | if length == 1 then .[0].digest else error("expected exactly one linux/\($arch) manifest") end
' <<<"$raw")"
[[ "$digest" =~ ^sha256:[a-f0-9]{64}$ ]] || { echo "invalid COSMIC source digest: $digest" >&2; exit 1; }
printf '%s@%s\n' "$repository" "$digest"
