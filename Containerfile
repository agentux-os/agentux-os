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
ARG AGENTUX_CORE_VERSION=0.1.0
ARG AGENTUX_DESKTOP_VERSION=0.1.0
ARG AGENTUX_PLASMA_SHA256=d12a3b73987dc493a744f7b5d96fe1daf9af0c4ed670d334adeca4a79a3262c0

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

# agentuxd runs as a user service for every user, like first-login. Fail the
# build if the packaged unit ever points at a binary that isn't there.
RUN chmod 0755 /usr/libexec/agentux/first-login \
    && exec_start="$(sed -n 's/^ExecStart=\([^ ]*\).*/\1/p' /usr/lib/systemd/user/agentuxd.service)" \
    && test -x "$exec_start" \
    && systemctl --global enable agentux-first-login.service agentuxd.service

LABEL org.opencontainers.image.title="AgentUX" \
      org.opencontainers.image.description="The Linux distribution where every coding agent works as one team" \
      org.opencontainers.image.source="https://github.com/agentux-os/agentux-os" \
      org.opencontainers.image.licenses="Apache-2.0" \
      containers.bootc="1"

RUN bootc container lint
