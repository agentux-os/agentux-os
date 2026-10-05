# AgentUX image: Fedora Kinoite (KDE Plasma, Wayland) as a bootc image.
# See ADR 0001 in agentux-os/agentux.

#
# One Containerfile, two images: VARIANT=plasma (the default) is
# ghcr.io/agentux-os/agentux; VARIANT=hyprland is
# ghcr.io/agentux-os/agentux-hyprland, the same system plus a Hyprland
# session that the login screen preselects (see the Hyprland step below).

ARG FEDORA_VERSION=44
FROM quay.io/fedora/fedora-kinoite:${FEDORA_VERSION}

ARG VARIANT=plasma
RUN case "$VARIANT" in plasma|hyprland) ;; *) echo "VARIANT must be plasma or hyprland, not '$VARIANT'" >&2; exit 1 ;; esac

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
ARG AGENTUX_CORE_VERSION=0.4.1
ARG AGENTUX_DESKTOP_VERSION=0.4.1
ARG AGENTUX_PLASMA_SHA256=5a2d2544cbfa22d689e58a7d27a0a88a68d65be75c00d2d0b18d320ea4618516

# agentux-core: aux, agentuxd and its systemd user unit. agentux-desktop: the
# cockpit, and the Plasma 6 defaults overlay (usr/ and etc/, relative to /),
# checked against the pinned sha256 before it touches the filesystem. Both
# releases ship x86_64 and aarch64 RPMs; the build runs natively on each
# architecture (see build.yml), so the build host's machine picks them. The
# Plasma overlay has no binaries and is the same for both.
RUN arch="$(uname -m)" \
    && case "$arch" in x86_64|aarch64) ;; *) echo "unsupported architecture $arch" >&2; exit 1 ;; esac \
    && core="https://github.com/agentux-os/agentux-core/releases/download/v${AGENTUX_CORE_VERSION}" \
    && desktop="https://github.com/agentux-os/agentux-desktop/releases/download/v${AGENTUX_DESKTOP_VERSION}" \
    && plasma="/tmp/agentux-plasma-${AGENTUX_DESKTOP_VERSION}.tar.gz" \
    && dnf -y install \
        "$core/agentux-${AGENTUX_CORE_VERSION}-1.fc44.${arch}.rpm" \
        "$desktop/agentux-cockpit-${AGENTUX_DESKTOP_VERSION}-1.${arch}.rpm" \
    && dnf clean all \
    && curl -fsSL "$desktop/${plasma#/tmp/}" -o "$plasma" \
    && printf '%s  %s\n' "$AGENTUX_PLASMA_SHA256" "$plasma" > "$plasma.sha256" \
    && sha256sum --check --strict "$plasma.sha256" \
    && tar -xzf "$plasma" -C / --no-same-owner --no-overwrite-dir \
    && rm -f "$plasma" "$plasma.sha256"

COPY files/ /

# The hyprland variant: Hyprland next to Plasma, as a second session that the
# login screen preselects. Plasma, the cockpit and everything else are the
# same as in the default image, so both sessions work and users can pick
# either at the login screen. Fedora 44 has no hyprland package; the
# sdegler/hyprland COPR (the one Fedora's Hyprland wiki points to) builds the
# Hyprland stack for Fedora 44 on x86_64 and aarch64. Its repository is left
# disabled afterwards, so `rpm-ostree install` on a system never pulls from
# it unasked. Waybar, fuzzel, mako, foot and the rest come from Fedora. Weak
# dependencies are off: they would add kitty, wofi, nwg-panel and uwsm, which
# nothing here uses. variants/hyprland/ holds the session (its Exec seeds ~/.config from
# /usr/share/agentux/hyprland/user/ when the user has no configuration of
# their own) and the AgentUX defaults; it is bind-mounted, so the plasma
# image carries none of it. The build fails if the defaults stop parsing.
RUN --mount=type=bind,source=variants,target=/tmp/variants \
    if [ "$VARIANT" != hyprland ]; then exit 0; fi \
    && copr=/etc/yum.repos.d/_copr_sdegler-hyprland.repo \
    && fedora="$(rpm -E %fedora)" \
    && curl -fsSL "https://copr.fedorainfracloud.org/coprs/sdegler/hyprland/repo/fedora-$fedora/sdegler-hyprland-fedora-$fedora.repo" -o "$copr" \
    && dnf -y install --setopt=install_weak_deps=False \
        brightnessctl \
        cliphist \
        foot \
        fuzzel \
        grim \
        hypridle \
        hyprland \
        hyprland-guiutils \
        hyprland-qt-support \
        hyprlock \
        hyprpolkitagent \
        mako \
        network-manager-applet \
        playerctl \
        slurp \
        swaybg \
        waybar \
        wl-clipboard \
        xdg-desktop-portal-hyprland \
    && dnf clean all \
    && sed -i 's/^enabled=1/enabled=0/' "$copr" \
    && cp -a /tmp/variants/hyprland/. / \
    && chmod 0755 /usr/libexec/agentux/hyprland-* \
    && test -x /usr/bin/start-hyprland \
    && test -f /usr/share/agentux/hyprland/wallpaper.png \
    && grep -qx 'Exec=/usr/libexec/agentux/hyprland-session' /usr/share/wayland-sessions/agentux-hyprland.desktop \
    && runtime="$(mktemp -d)" \
    && { XDG_RUNTIME_DIR="$runtime" Hyprland --i-am-really-stupid --verify-config \
        --config /usr/share/agentux/hyprland/user/hypr/hyprland.conf > /tmp/hyprland-verify.txt 2>&1 || true; } \
    && { grep -qx 'config ok' /tmp/hyprland-verify.txt || { cat /tmp/hyprland-verify.txt >&2; false; }; } \
    && rm -rf "$runtime" /tmp/hyprland-verify.txt \
    && foot --check-config --config /usr/share/agentux/hyprland/user/foot/foot.ini \
    && jq empty /usr/share/agentux/hyprland/user/waybar/config.jsonc

# Identity: the system calls itself AgentUX (os-release NAME is what the
# first-boot wizard's "Powered by", the boot menu, hostnamectl and KDE's About
# this System show), the way Universal Blue images rename Kinoite/Silverblue.
# Unlike them, ID stays fedora, with VERSION_ID, CPE_NAME, SUPPORT_END (and
# PLATFORM_ID, should the base set it again; Fedora 44's has none) as the
# base image has them: bootc-image-builder picks its Fedora 44 definitions
# by ID/VERSION_ID, dnf5 resolves $releasever from VERSION_ID, toolbox picks
# fedora-toolbox:<VERSION_ID> by ID, and scanners map CPE_NAME to Fedora's
# advisories; all of that is still true of this system. (Fedora sets no
# ID_LIKE, so there is none to keep.) Fedora's Bugzilla fields go: bug reports
# about this image belong to AgentUX. IMAGE_ID/IMAGE_VERSION are systemd's
# fields for image-based systems; the version is the build date (the dated
# tag's), or AGENTUX_VERSION if given. LOGO names the brand icon installed in
# hicolor and /usr/share/pixmaps by files/. /etc/os-release is a symlink here.
# The base image's os-release is kept as /usr/share/agentux/os-release.base,
# so the smoke and boot tests check the kept fields against the real values.
ARG AGENTUX_VERSION=""
RUN version="${AGENTUX_VERSION:-$(date -u +%Y%m%d)}" \
    && fedora="$(. /usr/lib/os-release && test "$ID" = fedora && echo "$VERSION_ID")" \
    && test -n "$fedora" \
    && base=/usr/share/agentux/os-release.base \
    && mkdir -p /usr/share/agentux \
    && cp /usr/lib/os-release "$base" \
    && set_field() { \
        awk -v k="$1" -v v="$2" \
            'index($0, k "=") == 1 { if (!done) print k "=\"" v "\""; done = 1; next } { print } END { if (!done) print k "=\"" v "\"" }' \
            /usr/lib/os-release > /tmp/os-release && cat /tmp/os-release > /usr/lib/os-release; \
    } \
    && set_field NAME "AgentUX" \
    && set_field VERSION "$version (Fedora Linux $fedora base)" \
    && set_field PRETTY_NAME "AgentUX $version (Fedora Linux $fedora base)" \
    && case "$VARIANT" in \
        hyprland) image=agentux-hyprland variant=Hyprland ;; \
        *) image=agentux variant=Plasma ;; \
    esac \
    && set_field VARIANT "$variant" \
    && set_field VARIANT_ID "$image" \
    && set_field IMAGE_ID "$image" \
    && set_field IMAGE_VERSION "$version" \
    && set_field LOGO "agentux" \
    && set_field ANSI_COLOR "0;38;2;198;243;107" \
    && set_field DEFAULT_HOSTNAME "agentux" \
    && set_field HOME_URL "https://github.com/agentux-os/agentux" \
    && set_field DOCUMENTATION_URL "https://github.com/agentux-os/agentux-os#readme" \
    && set_field SUPPORT_URL "https://github.com/agentux-os/agentux/issues" \
    && set_field BUG_REPORT_URL "https://github.com/agentux-os/agentux-os/issues" \
    && sed -i '/^REDHAT_BUGZILLA_PRODUCT/d' /usr/lib/os-release \
    && rm /tmp/os-release \
    && test "$(readlink -f /etc/os-release)" = /usr/lib/os-release \
    && for key in ID VERSION_ID PLATFORM_ID CPE_NAME SUPPORT_END; do \
        test "$(grep "^$key=" /usr/lib/os-release)" = "$(grep "^$key=" "$base")" || exit 1; \
    done \
    && (. /usr/lib/os-release && test "$NAME" = AgentUX && test "$ID" = fedora && test "$LOGO" = agentux) \
    && test -f /usr/share/icons/hicolor/scalable/apps/agentux.svg \
    && gtk-update-icon-cache --force --quiet /usr/share/icons/hicolor \
    && cat /usr/lib/os-release

# Boot splash: the AgentUX Plymouth theme (files/usr/share/plymouth/themes/
# agentux, a script-plugin theme; its images come from plymouth/build.py).
# Plymouth runs from the initramfs, which in a bootc image is built here, not
# on the installed system: regenerate the kernel's /usr/lib/modules/$kver/
# initramfs.img with the theme in it, the way Universal Blue images do
# (generic, not host-only, with ostree's module, reproducible), and fail the
# build if the theme or its plugin is missing from it. Same on x86_64 and
# aarch64. The splash shows when the kernel command line has rhgb, which
# files/usr/lib/bootc/kargs.d/10-agentux-splash.toml adds.
RUN dnf -y install plymouth-plugin-script \
    && dnf clean all \
    && plymouth-set-default-theme agentux \
    && test "$(plymouth-set-default-theme)" = agentux \
    && set -- /usr/lib/modules/* \
    && test "$#" = 1 \
    && kver="${1##*/}" \
    && img="/usr/lib/modules/$kver/initramfs.img" \
    && DRACUT_NO_XATTR=1 dracut --no-hostonly --kver "$kver" --reproducible --add ostree --force "$img" \
    && lsinitrd "$img" > /tmp/initramfs.txt \
    && grep -q 'usr/share/plymouth/themes/agentux/agentux.script$' /tmp/initramfs.txt \
    && grep -q 'usr/share/plymouth/themes/agentux/dashes.png$' /tmp/initramfs.txt \
    && grep -q '/plymouth/script.so$' /tmp/initramfs.txt \
    && rm /tmp/initramfs.txt \
    && chmod 0644 "$img"

# Updates of this image (bootc upgrade/switch pull through containers/image)
# must carry a cosign signature from the AgentUX key shipped in files/. Only
# AgentUX's repositories get the requirement, both variants' in both images,
# so a `bootc switch` from one variant to the other is checked too: Fedora's
# policy for everything else, including its insecureAcceptAnything default,
# is kept as is. The policy can't check keyless (Fulcio) signatures from
# GitHub Actions, since it only matches e-mail identities; CI signs both ways
# (see build.yml).
RUN jq --arg key /etc/pki/containers/agentux-os.pub \
        '[{"type": "sigstoreSigned", "keyPath": $key, "signedIdentity": {"type": "matchRepository"}}] as $signed | .transports.docker["ghcr.io/agentux-os/agentux"] = $signed | .transports.docker["ghcr.io/agentux-os/agentux-hyprland"] = $signed' \
        /etc/containers/policy.json > /tmp/policy.json \
    && jq -e '.default and .transports.docker["ghcr.io/agentux-os/agentux"] and .transports.docker["ghcr.io/agentux-os/agentux-hyprland"]' /tmp/policy.json > /dev/null \
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
      io.github.agentux-os.variant="${VARIANT}" \
      containers.bootc="1"

RUN bootc container lint
