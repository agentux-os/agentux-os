# AgentUX image: Fedora Atomic Desktop as a bootc image.
# See ADR 0001 in agentux-os/agentux.

#
# One Containerfile, two images: VARIANT=plasma (the default) is
# ghcr.io/agentux-os/agentux; VARIANT=cosmic is a separate COSMIC-only
# desktop image, ghcr.io/agentux-os/agentux-cosmic. (The Hyprland variant,
# ghcr.io/agentux-os/agentux-hyprland, was retired after v0.5.9.)

ARG FEDORA_VERSION=44
ARG BASE_IMAGE=quay.io/fedora/fedora-kinoite:${FEDORA_VERSION}
FROM ${BASE_IMAGE}

ARG VARIANT=plasma
RUN case "$VARIANT" in plasma|cosmic) ;; *) echo "VARIANT must be plasma or cosmic, not '$VARIANT'" >&2; exit 1 ;; esac

# mise is not in the Fedora repos; use its official RPM repository.
RUN curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 https://mise.jdx.dev/rpm/mise.repo -o /etc/yum.repos.d/mise.repo

# System toolchain. Fast-moving, per-user tools (agent CLIs, bun, lazygit,
# ast-grep) are installed on first login instead; see files/usr/libexec.
# libsecret: secret-tool, which keeps the agents' API keys in the desktop's
# secret service (the cockpit's Settings) for agentuxd to hand them over.
RUN dnf -y install \
        bat \
        distrobox \
        fd-find \
        gh \
        git \
        git-delta \
        jq \
        just \
        libsecret \
        mise \
        nodejs \
        npm \
        ripgrep \
        unzip \
        uv \
    && dnf clean all

# Fedora's COSMIC Atomic base already supplies the desktop. Add only the
# Anaconda/Initial Setup bridge required by AgentUX's live installer.
RUN if [ "$VARIANT" = cosmic ]; then \
        dnf -y install initial-setup-gui initial-setup-gui-wayland-cosmic \
        && dnf clean all; \
    fi

# Fail early if a wrong base or an incomplete installer integration was passed.
RUN if [ "$VARIANT" = cosmic ]; then \
        rpm -q cosmic-session || { echo "COSMIC Atomic base is missing the cosmic-session RPM" >&2; exit 1; }; \
        test -x /usr/bin/start-cosmic || { echo "COSMIC Atomic base is missing /usr/bin/start-cosmic" >&2; exit 1; }; \
        test -x /usr/libexec/initial-setup/run-gui-backend || { echo "COSMIC Atomic base is missing Fedora Initial Setup GUI backend" >&2; exit 1; }; \
    fi

# AgentUX itself, pinned to GitHub releases in this one place.
# `just bump-agentux` moves the pins to the latest releases (pre-releases
# included) and recomputes the desktop overlay checksums.
ARG AGENTUX_CORE_VERSION=0.5.0
ARG AGENTUX_DESKTOP_VERSION=0.5.11
ARG AGENTUX_PLASMA_SHA256=d0f7415703a805f32c07d65dc42a46e2dd9634383b7b82131e494e1f89d5876b
ARG AGENTUX_COMMON_SHA256=c16731b34e2a6a3ff753bcee68c3781e4e15051d9bb7bfa4aa53bc6357ddfc42
ARG AGENTUX_COSMIC_SHA256=32b9006d56bd10c27248b8ab289b426e33e523147e0e92ff07df4a1c2ab7a131

# agentux-core: aux, agentuxd and its systemd user unit. agentux-desktop: the
# cockpit RPM plus desktop overlays (usr/ and etc/, relative to /), checked
# against pinned SHA-256 values before extraction. The common overlay is
# paired with either the Plasma or COSMIC desktop overlay.
RUN arch="$(uname -m)" \
    && case "$arch" in x86_64|aarch64) ;; *) echo "unsupported architecture $arch" >&2; exit 1 ;; esac \
    && core="https://github.com/agentux-os/agentux-core/releases/download/v${AGENTUX_CORE_VERSION}" \
    && desktop="https://github.com/agentux-os/agentux-desktop/releases/download/v${AGENTUX_DESKTOP_VERSION}" \
    && dnf -y install \
        "$core/agentux-${AGENTUX_CORE_VERSION}-1.fc44.${arch}.rpm" \
        "$desktop/agentux-cockpit-${AGENTUX_DESKTOP_VERSION}-1.${arch}.rpm" \
    && dnf clean all \
    && test -n "$AGENTUX_COMMON_SHA256" \
    && common="agentux-desktop-common-${AGENTUX_DESKTOP_VERSION}.tar.gz" \
    && curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 "$desktop/$common" -o "/tmp/$common" \
    && printf '%s  %s\n' "$AGENTUX_COMMON_SHA256" "/tmp/$common" > /tmp/common.sha256 \
    && sha256sum --check --strict /tmp/common.sha256 \
    && tar -xzf "/tmp/$common" -C / --no-same-owner --no-overwrite-dir \
    && rm -f "/tmp/$common" /tmp/common.sha256 \
    && if [ "$VARIANT" = cosmic ]; then \
        test -n "$AGENTUX_COSMIC_SHA256" \
        && cosmic="agentux-desktop-cosmic-${AGENTUX_DESKTOP_VERSION}.tar.gz" \
        && curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 "$desktop/$cosmic" -o "/tmp/$cosmic" \
        && printf '%s  %s\n' "$AGENTUX_COSMIC_SHA256" "/tmp/$cosmic" > /tmp/cosmic.sha256 \
        && sha256sum --check --strict /tmp/cosmic.sha256 \
        && tar -xzf "/tmp/$cosmic" -C / --no-same-owner --no-overwrite-dir \
        && rm -f "/tmp/$cosmic" /tmp/cosmic.sha256; \
    else \
        plasma="agentux-desktop-plasma-${AGENTUX_DESKTOP_VERSION}.tar.gz" \
        && curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 "$desktop/$plasma" -o "/tmp/$plasma" \
        && printf '%s  %s\n' "$AGENTUX_PLASMA_SHA256" "/tmp/$plasma" > "/tmp/$plasma.sha256" \
        && sha256sum --check --strict "/tmp/$plasma.sha256" \
        && tar -xzf "/tmp/$plasma" -C / --no-same-owner --no-overwrite-dir \
        && rm -f "/tmp/$plasma" "/tmp/$plasma.sha256"; \
    fi

COPY files/ /

# Identity: the system calls itself AgentUX, with AgentUX's version, wherever
# people look (os-release's PRETTY_NAME is what the boot menu entries, the
# installers' title bars, hostnamectl and KDE's About this System show), the
# way Universal Blue images rename Kinoite/Silverblue. Unlike them, ID stays
# fedora, with VERSION_ID, CPE_NAME, SUPPORT_END (and PLATFORM_ID, should the
# base set it again; Fedora 44's has none) as the base image has them:
# bootc-image-builder picks its Fedora 44 definitions by ID/VERSION_ID, dnf5
# resolves $releasever from VERSION_ID, toolbox picks
# fedora-toolbox:<VERSION_ID> by ID, and scanners map CPE_NAME to Fedora's
# advisories; all of that is still true of this system. (Fedora sets no
# ID_LIKE, so there is none to keep.) Fedora's Bugzilla fields go: bug reports
# about this image belong to AgentUX. See ADR 0012 in agentux-os/agentux.
#
# The version is the build's, because a release does not rebuild: it
# promotes main's already-built image to :<tag> and :stable (release.yml), so
# no file in the image can name the release. AGENTUX_VERSION (build.yml passes
# <date>.<short commit>, e.g. 2026.10.15.063578e) is IMAGE_VERSION and
# BUILD_ID; VERSION and PRETTY_NAME carry its date ("AgentUX 2026.10.15").
# A local build without it gets today's date. Which release and channel a
# system runs is read at run time from the booted image (agentux-version,
# and the Release line of KDE's About page). The Fedora base is named where
# it is labelled as the base (agentux-version, the About page's "Based on"),
# from the base image's os-release, kept as /usr/share/agentux/os-release.base
# (the smoke and boot tests also check the kept fields against it).
# /etc/system-release (Fedora's symlink to fedora-release) becomes "AgentUX
# release <date>": bootupd names the firmware's boot entry after it (the
# "Fedora" entry in a UEFI boot menu), and liveinst takes the installer's
# product name and version from it. /etc/os-release is a symlink here.
# LOGO names the brand icon installed in hicolor and /usr/share/pixmaps by
# files/.
ARG AGENTUX_VERSION=""
ARG AGENTUX_COMMIT=""
# The pipes only feed printf into grep and sed (no failure to hide), and
# VERSION is os-release's, read in a subshell.
# hadolint ignore=DL4006,SC2153
RUN version="${AGENTUX_VERSION:-$(date -u +%Y.%m.%d)}" \
    && printf '%s\n' "$version" | grep -Eqx '[0-9a-z._-]+' \
    && date="$(printf '%s\n' "$version" | sed -nE 's/^([0-9]{4}\.[0-9]{2}\.[0-9]{2})(\.[0-9a-f]+)?$/\1/p')" \
    && date="${date:-$version}" \
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
    && set_field VERSION "$date" \
    && set_field PRETTY_NAME "AgentUX $date" \
    && case "$VARIANT" in \
        cosmic) image=agentux-cosmic variant=COSMIC ;; \
        *) image=agentux variant=Plasma ;; \
    esac \
    && set_field VARIANT "$variant" \
    && set_field VARIANT_ID "$image" \
    && set_field IMAGE_ID "$image" \
    && set_field IMAGE_VERSION "$version" \
    && set_field BUILD_ID "$version" \
    && set_field LOGO "agentux" \
    && set_field ANSI_COLOR "0;38;2;198;243;107" \
    && set_field DEFAULT_HOSTNAME "agentux" \
    && set_field HOME_URL "https://agentuxos.org" \
    && set_field DOCUMENTATION_URL "https://github.com/agentux-os/agentux#readme" \
    && set_field SUPPORT_URL "https://github.com/agentux-os/agentux/issues" \
    && set_field BUG_REPORT_URL "https://github.com/agentux-os/agentux-os/issues" \
    && sed -i '/^REDHAT_BUGZILLA_PRODUCT/d; /^REDHAT_SUPPORT_PRODUCT/d' /usr/lib/os-release \
    && rm /tmp/os-release \
    && test "$(readlink -f /etc/os-release)" = /usr/lib/os-release \
    && for key in ID VERSION_ID PLATFORM_ID CPE_NAME SUPPORT_END; do \
        test "$(grep "^$key=" /usr/lib/os-release)" = "$(grep "^$key=" "$base")" || exit 1; \
    done \
    && (. /usr/lib/os-release && test "$NAME" = AgentUX && test "$ID" = fedora && test "$LOGO" = agentux \
        && test "$PRETTY_NAME" = "AgentUX $VERSION" && ! echo "$PRETTY_NAME" | grep -q Fedora) \
    && rm -f /etc/system-release \
    && echo "AgentUX release $date" > /etc/system-release \
    && test "$(sed -E 's/ *release.*//' /etc/system-release)" = AgentUX \
    && printf '%s\n' "${AGENTUX_COMMIT}" > /usr/share/agentux/commit \
    && test -f /usr/share/icons/hicolor/scalable/apps/agentux.svg \
    && gtk-update-icon-cache --force --quiet /usr/share/icons/hicolor \
    && chmod 0755 /usr/bin/agentux-version /usr/libexec/agentux/about-release /usr/libexec/agentux/about-base \
    && /usr/libexec/agentux/about-base > /tmp/about-base \
    && test "$(sed -n 1p /tmp/about-base)" = "Based on:" \
    && grep -qx "Fedora Linux $fedora.*" /tmp/about-base \
    && rm /tmp/about-base \
    && systemctl enable agentux-releases.timer \
    && chmod 0755 /usr/libexec/agentux/stage-update \
    && bash -n /usr/libexec/agentux/stage-update \
    && systemctl enable agentux-update.timer \
    && { systemctl disable bootc-fetch-apply-updates.timer 2>/dev/null || true; } \
    && ! test -e /etc/systemd/system/timers.target.wants/bootc-fetch-apply-updates.timer \
    && cat /usr/lib/os-release /etc/system-release

# Fedora's Default wallpaper is AgentUX's. plasma-setup's first-boot wizard
# hard-codes its background (a Fedora patch): wallpapers/Default/contents/
# images_dark/ (images/ for a light theme), 5120x2880.jxl on a landscape
# screen, 1440x2960.jxl on a portrait one, scaled to cover. In Fedora,
# Default is a symlink (desktop-backgrounds-kde's) to the F44 package
# (f44-backgrounds-kde's). Point it, and so Fedora -> Default too, at an
# AgentUX package with those files, rendered here with ImageMagick (in the
# base image, with librsvg and libjxl) from wallpaper/wizard-*.svg: the
# brand's key art (wallpaper/wallpaper-*.svg, copied from brand/art/ in
# agentux-os/agentux) with the mark moved smaller to the lower third by
# wallpaper/build.py, clear of the wizard's centred text and buttons; the
# portrait file is the middle of it. The F44 package
# stays as it is. Whatever else falls back to Default (the login screen
# without its AgentUX drop-in, new wallpaper settings) gets AgentUX too.
# `rpm -V desktop-backgrounds-kde` reports the changed symlink; that is this.
RUN --mount=type=bind,source=wallpaper,target=/tmp/wallpaper \
    if [ "$VARIANT" = cosmic ]; then exit 0; fi \
    && command -v magick > /dev/null \
    && wallpapers=/usr/share/wallpapers \
    && pkg="$wallpapers/AgentUX-Default" \
    && mkdir -p "$pkg/contents/images" "$pkg/contents/images_dark" \
    && cp /tmp/wallpaper/metadata.json "$pkg/metadata.json" \
    && for variant in light:images dark:images_dark; do \
        svg="/tmp/wallpaper/wizard-${variant%%:*}.svg" \
        && out="$pkg/contents/${variant#*:}" \
        && magick -density 128 "$svg" -alpha off -depth 8 -quality 90 "$out/5120x2880.jxl" \
        && magick -density 131.5556 "$svg" -alpha off -crop 1440x2960+1911+0 +repage -depth 8 -quality 90 "$out/1440x2960.jxl" \
        && test "$(magick identify -format '%m %wx%h' "$out/5120x2880.jxl")" = "JXL 5120x2880" \
        && test "$(magick identify -format '%m %wx%h' "$out/1440x2960.jxl")" = "JXL 1440x2960" \
        || exit 1; \
    done \
    && { test -L "$wallpapers/Default" || ! test -e "$wallpapers/Default"; } \
    && ln -sfn AgentUX-Default "$wallpapers/Default" \
    && for f in images/5120x2880.jxl images/1440x2960.jxl images_dark/5120x2880.jxl images_dark/1440x2960.jxl; do \
        test "$(readlink -f "$wallpapers/Default/contents/$f")" = "$pkg/contents/$f" || exit 1; \
    done \
    && jq -e '.KPlugin.Id == "AgentUX-Default"' "$wallpapers/Default/metadata.json" > /dev/null \
    && ls -ld "$wallpapers/Default" "$pkg"/contents/*/*

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
    && grep -q 'usr/share/plymouth/themes/agentux/water.png$' /tmp/initramfs.txt \
    && grep -q '/plymouth/script.so$' /tmp/initramfs.txt \
    && rm /tmp/initramfs.txt \
    && chmod 0644 "$img"

# GRUB menu: the AgentUX look (files/usr/share/agentux/grub/, background from
# grub/build.py). GRUB reads only the boot partition, which an image cannot
# ship files into, and bootupd's static grub.cfg there is written once at
# install time; it does source $prefix/console.cfg, "GRUB console settings
# provided by the user/platform", before drawing the menu. So
# agentux-grub-theme.service copies console.cfg and the theme there at boot,
# never touching grub.cfg, the boot entries or grubenv (see
# /usr/libexec/agentux/grub-theme). Fail the build if bootupd's static
# config stops sourcing console.cfg. The font is GRUB's Unifont.
# GRUB's boot-success flag (grub-boot-success.timer, a user unit, runs
# grub2-set-bootflag two minutes into a session) is for grub2-mkconfig's
# menu_auto_hide; bootupd's static grub.cfg always shows the menu and never
# reads it, and bootc mounts /boot read-only, so the service could only fail.
# Disable the timer and mask the service, as the live layer does.
RUN chmod 0755 /usr/libexec/agentux/grub-theme \
    && grep -q 'console\.cfg' /usr/lib/bootupd/grub2-static/grub-static-pre.cfg \
    && cp /usr/share/grub/unicode.pf2 /usr/share/agentux/grub/unicode.pf2 \
    && test -f /usr/share/agentux/grub/theme.txt \
    && test -f /usr/share/agentux/grub/background.png \
    && systemctl enable agentux-grub-theme.service \
    && if systemctl --global cat grub-boot-success.timer >/dev/null 2>&1; then systemctl --global disable grub-boot-success.timer; fi \
    && if systemctl --global cat grub-boot-success.service >/dev/null 2>&1; then systemctl --global mask grub-boot-success.service; fi \
    && test ! -e /etc/systemd/user/timers.target.wants/grub-boot-success.timer

# Updates of this image (bootc upgrade/switch pull through containers/image)
# must carry a cosign signature from the AgentUX key shipped in files/. Only
# AgentUX's repositories get the requirement in every image, so a `bootc
# switch` between variants is checked too; agentux-hyprland keeps it after
# the variant's retirement, as its last images stay in the registry. Fedora's
# policy for everything else, including its insecureAcceptAnything default,
# is kept as is. The policy can't check keyless (Fulcio) signatures from
# GitHub Actions, since it only matches e-mail identities; CI signs both ways
# (see build.yml).
RUN jq --arg key /etc/pki/containers/agentux-os.pub \
        '[{"type": "sigstoreSigned", "keyPath": $key, "signedIdentity": {"type": "matchRepository"}}] as $signed | .transports.docker["ghcr.io/agentux-os/agentux"] = $signed | .transports.docker["ghcr.io/agentux-os/agentux-hyprland"] = $signed | .transports.docker["ghcr.io/agentux-os/agentux-cosmic"] = $signed' \
        /etc/containers/policy.json > /tmp/policy.json \
    && jq -e '.default and .transports.docker["ghcr.io/agentux-os/agentux"] and .transports.docker["ghcr.io/agentux-os/agentux-hyprland"] and .transports.docker["ghcr.io/agentux-os/agentux-cosmic"]' /tmp/policy.json > /dev/null \
    && cat /tmp/policy.json > /etc/containers/policy.json \
    && rm /tmp/policy.json

# agentuxd runs as a user service for every user, like first-login. Fail the
# build if the packaged unit ever points at a binary that isn't there, or
# stops skipping system users (ConditionUser=!@system, packaged since
# agentux-core 0.4.0: the user managers of system users with a session, like
# plasma-setup's first-boot wizard, must not start it), or if nm-online
# (NetworkManager), which first-login waits for the network with, goes missing.
RUN chmod 0755 /usr/libexec/agentux/first-login \
    && chmod 0755 /usr/bin/agentux \
    && chmod 0755 /usr/libexec/agentux/profile-command \
    && jq empty /usr/share/agentux/profiles/catalog.json \
    && jq -e '.profiles.workstation.components | index("node") and index("desktop")' /usr/share/agentux/profiles/catalog.json > /dev/null \
    && exec_start="$(sed -n 's/^ExecStart=\([^ ]*\).*/\1/p' /usr/lib/systemd/user/agentuxd.service)" \
    && test -x "$exec_start" \
    && grep -qx 'ConditionUser=!@system' /usr/lib/systemd/user/agentuxd.service \
    && test -x /usr/bin/nm-online \
    && systemctl --global enable agentux-first-login.service agentux-antigravity-acp.service agentuxd.service \
    && systemctl enable agentux-profile-apply.service agentux-provision.service

LABEL org.opencontainers.image.title="AgentUX" \
      org.opencontainers.image.description="The Linux distribution where every coding agent works as one team" \
      org.opencontainers.image.source="https://github.com/agentux-os/agentux-os" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="${AGENTUX_VERSION}" \
      org.opencontainers.image.revision="${AGENTUX_COMMIT}" \
      io.github.agentux-os.variant="${VARIANT}" \
      io.github.agentux-os.base-image="${BASE_IMAGE}" \
      containers.bootc="1"

RUN bootc container lint
