#!/usr/bin/env bash
# next-patch.sh: the tag of the next patch release, from the newest vX.Y.Z
# tag in this repository (v0.6.5 -> v0.6.6). Run with the tags fetched.
set -euo pipefail

latest=$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1)
[[ -n "$latest" ]] || { echo "no vX.Y.Z tag yet" >&2; exit 1; }
IFS=. read -r major minor patch <<<"${latest#v}"
echo "v$major.$minor.$((patch + 1))"
