# AgentUX image: Fedora Kinoite (KDE Plasma, Wayland) as a bootc image.
# See ADR 0001 in agentux-os/agentux.

ARG FEDORA_VERSION=44
FROM quay.io/fedora/fedora-kinoite:${FEDORA_VERSION}

# mise is not in the Fedora repos; use its official RPM repository.
RUN curl -fsSL https://mise.jdx.dev/rpm/mise.repo -o /etc/yum.repos.d/mise.repo

# System toolchain. Fast-moving, per-user tools (agent CLIs, bun, lazygit,
# ast-grep) are installed on first login instead; see files/usr/libexec.
RUN dnf -y install \
        bat \
        distrobox \
        fd-find \
        gh \
        git \
        git-delta \
        jq \
        just \
        mise \
        nodejs \
        npm \
        ripgrep \
        unzip \
        uv \
    && dnf clean all

# AgentUX itself, pinned to GitHub releases in this one place.
# `just bump-agentux` moves the pins to the latest releases (pre-releases
# included) and recomputes the Plasma overlay checksum.
ARG AGENTUX_CORE_VERSION=0.4.0
ARG AGENTUX_DESKTOP_VERSION=0.4.0
ARG AGENTUX_PLASMA_SHA256=cf82bc5c343a11a7382215ac3b083f085e4c663eb8449bfc8ac85a3212142c30

# agentux-core: aux, agentuxd and its systemd user unit. agentux-desktop: the
# cockpit, and the Plasma 6 defaults overlay (usr/ and etc/, relative to /),
# checked against the pinned sha256 before it touches the filesystem.
RUN core="https://github.com/agentux-os/agentux-core/releases/download/v${AGENTUX_CORE_VERSION}" \
    && desktop="https://github.com/agentux-os/agentux-desktop/releases/download/v${AGENTUX_DESKTOP_VERSION}" \
    && plasma="/tmp/agentux-plasma-${AGENTUX_DESKTOP_VERSION}.tar.gz" \
    && dnf -y install \
        "$core/agentux-${AGENTUX_CORE_VERSION}-1.fc44.x86_64.rpm" \
        "$desktop/agentux-cockpit-${AGENTUX_DESKTOP_VERSION}-1.x86_64.rpm" \
    && dnf clean all \
    && curl -fsSL "$desktop/${plasma#/tmp/}" -o "$plasma" \
    && printf '%s  %s\n' "$AGENTUX_PLASMA_SHA256" "$plasma" > "$plasma.sha256" \
    && sha256sum --check --strict "$plasma.sha256" \
    && tar -xzf "$plasma" -C / --no-same-owner --no-overwrite-dir \
    && rm -f "$plasma" "$plasma.sha256"

COPY files/ /

# Updates of this image (bootc upgrade/switch pull through containers/image)
# must carry a cosign signature from the AgentUX key shipped in files/. Only
# this repository gets the requirement: Fedora's policy for everything else,
# including its insecureAcceptAnything default, is kept as is. The policy
# can't check keyless (Fulcio) signatures from GitHub Actions, since it only
# matches e-mail identities; CI signs both ways (see build.yml).
RUN jq --arg key /etc/pki/containers/agentux-os.pub \
        '.transports.docker["ghcr.io/agentux-os/agentux"] = [{"type": "sigstoreSigned", "keyPath": $key, "signedIdentity": {"type": "matchRepository"}}]' \
        /etc/containers/policy.json > /tmp/policy.json \
    && jq -e '.default and .transports.docker["ghcr.io/agentux-os/agentux"]' /tmp/policy.json > /dev/null \
    && cat /tmp/policy.json > /etc/containers/policy.json \
    && rm /tmp/policy.json

# agentuxd runs as a user service for every user, like first-login. Fail the
# build if the packaged unit ever points at a binary that isn't there, or
# stops skipping system users (ConditionUser=!@system, packaged since
# agentux-core 0.4.0: the user managers of system users with a session, like
# plasma-setup's first-boot wizard, must not start it), or if nm-online
# (NetworkManager), which first-login waits for the network with, goes missing.
RUN chmod 0755 /usr/libexec/agentux/first-login \
    && exec_start="$(sed -n 's/^ExecStart=\([^ ]*\).*/\1/p' /usr/lib/systemd/user/agentuxd.service)" \
    && test -x "$exec_start" \
    && grep -qx 'ConditionUser=!@system' /usr/lib/systemd/user/agentuxd.service \
    && test -x /usr/bin/nm-online \
    && systemctl --global enable agentux-first-login.service agentux-antigravity-acp.service agentuxd.service

LABEL org.opencontainers.image.title="AgentUX" \
      org.opencontainers.image.description="The Linux distribution where every coding agent works as one team" \
      org.opencontainers.image.source="https://github.com/agentux-os/agentux-os" \
      org.opencontainers.image.licenses="Apache-2.0" \
      containers.bootc="1"

RUN bootc container lint
