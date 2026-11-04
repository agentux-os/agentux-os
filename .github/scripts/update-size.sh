#!/usr/bin/env bash
# What a system on image FROM downloads to update to image TO: the layers of
# TO that FROM does not have (ADR 0019, agentux-os#75). Both are image
# references skopeo reads, e.g. docker://ghcr.io/agentux-os/agentux:20261104.
# --arch picks an architecture from a manifest list (default amd64).
#
#   .github/scripts/update-size.sh [--arch arm64] FROM TO
set -euo pipefail

arch=amd64
if [ "${1:-}" = --arch ]; then
    arch="$2"
    shift 2
fi
[ "$#" = 2 ] || { echo "usage: $0 [--arch ARCH] FROM TO" >&2; exit 2; }

layers() {
    skopeo inspect --override-os linux --override-arch "$arch" --raw "$1" > /dev/null
    skopeo inspect --override-os linux --override-arch "$arch" "$1" \
        | jq -r '.LayersData[] | "\(.Digest) \(.Size)"'
}

from="$(layers "$1")"
to="$(layers "$2")"

awk -v from="$from" '
    BEGIN { n = split(from, f, "\n"); for (i = 1; i <= n; i++) { split(f[i], p, " "); have[p[1]] = 1 } }
    { total += $2; count++; if (!($1 in have)) { new += $2; changed++ } }
    END {
        printf "layers: %d, of which %d new\n", count, changed
        printf "image: %.1f MiB, update: %.1f MiB (%.1f%%)\n", total / 1048576, new / 1048576, total ? 100 * new / total : 0
    }
' <<<"$to"
