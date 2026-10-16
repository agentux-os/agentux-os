#!/usr/bin/bash
# Picks the channel an ISO's installed system follows, for iso.yml and
# live.yml, and writes to GITHUB_ENV:
#
#   TRACK_IMAGE    <repo>:<channel>, what `bootc upgrade` follows after the
#                  install (the origin bootc-image-builder's and the live
#                  installer's `bootc switch` write)
#   INSTALL_IMAGE  what the live installer pulls from the registry: IMAGE
#                  when it is a digest (a release ISO installs exactly the
#                  tag's image), TRACK_IMAGE otherwise
#
# Environment: IMAGE (what the ISO is built from), REPO (the variant's
# repository), CHANNEL (stable or latest), TOKEN (to read ghcr.io).
#
# Until the first release is promoted there is no :stable. A dispatch asking
# for it then falls back to :latest with a warning, so no ISO ever points at
# a tag that does not exist. A tag build (release.yml) never falls back: its
# release job moves :stable to the tag's image before it publishes the ISOs.
set -euo pipefail

: "${IMAGE:?}" "${REPO:?}" "${CHANNEL:?}"
case "$CHANNEL" in
    stable | latest) ;;
    *) echo "::error::unknown channel '$CHANNEL' (stable or latest)"; exit 1 ;;
esac

# COSMIC is experimental/nightly-only until install, signatures, both
# architectures, and rollback have passed the launch gate. Never let a
# reusable workflow or tag accidentally build a stable COSMIC ISO.
if [[ "$REPO" == */agentux-cosmic && ( "$CHANNEL" == stable || ${GITHUB_REF:-} == refs/tags/v* ) ]]; then
    echo "::error::COSMIC Live is nightly-only; stable/release ISO builds are gated"
    exit 1
fi

if [[ ${GITHUB_REF:-} == refs/tags/v* ]]; then
    if [[ $CHANNEL != stable || $IMAGE != "$REPO"@sha256:* ]]; then
        echo "::error::a release ISO must be built from a digest of $REPO and follow :stable (got $IMAGE, $CHANNEL)"
        exit 1
    fi
elif [[ $CHANNEL == stable ]] \
    && ! skopeo inspect --raw --creds "${GITHUB_ACTOR:-x}:${TOKEN:-}" "docker://$REPO:stable" >/dev/null 2>&1; then
    echo "::warning::$REPO:stable does not exist yet (no release has been promoted); this ISO follows :latest instead"
    CHANNEL=latest
fi

track="$REPO:$CHANNEL"
if [[ $IMAGE == "$REPO"@sha256:* ]]; then install=$IMAGE; else install=$track; fi
{
    echo "TRACK_IMAGE=$track"
    echo "INSTALL_IMAGE=$install"
} >>"${GITHUB_ENV:-/dev/stdout}"
echo "built from $IMAGE; installs $install; follows $track"
