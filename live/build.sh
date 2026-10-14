#!/usr/bin/bash
# Turns an AgentUX image into the AgentUX live environment; run by
# live/Containerfile with this directory mounted at /tmp/live. Live-only
# changes go here, never into the image itself (the installer installs the
# published image from the registry, so nothing from here reaches an
# installed system):
#
#   - a live boot: dracut's dmsquash-live in the initramfs, GRUB entries in
#     /usr/lib/bootc-image-builder/iso.yaml and the EFI binaries Titanoboa
#     copies onto the ISO;
#   - livesys-scripts: a passwordless `liveuser` logged in automatically
#     into Plasma (or AgentUX Hyprland), with Fedora's live tweaks;
#   - no ~1 GB of downloads into RAM at login: the agent CLIs' first-login
#     unit is not started at login but on demand (a desktop launcher), and
#     the Antigravity ACP server is skipped altogether;
#   - a demo: agentuxd with --fake-agents and a sample project whose runs
#     the cockpit shows moving, explained by a note on the desktop;
#   - the installer: Anaconda (liveinst), started by "Install AgentUX", which
#     installs the signed image from the registry (INSTALL_IMAGE: the
#     channel's tag, or a release's digest) and leaves the system following
#     TRACK_IMAGE (ghcr.io/agentux-os/<image>:stable or :latest);
#   - qemu-guest-agent, so VMs (and the live test) can talk to the session.
#
# Live mode is detectable at run time: rd.live.image on the kernel command
# line (what livesys and the live units here check) and the marker
# /usr/share/agentux/live/marker, which only this layer ships.
set -euxo pipefail

src=/tmp/live
# shellcheck source=/dev/null
. /usr/lib/os-release
case "${IMAGE_ID:-}" in
    agentux) label=AgentUX-Live title=AgentUX ;;
    agentux-hyprland) label=AgentUX-Hyprland-Live title="AgentUX Hyprland" ;;
    *) echo "not an AgentUX image (IMAGE_ID=${IMAGE_ID:-unset})" >&2; exit 1 ;;
esac
# What "Install AgentUX" installs: the published, signed image of the same
# variant (INSTALL_IMAGE, a tag or a digest), and the channel the installed
# system then tracks for updates (TRACK_IMAGE). Both come from live.yml as
# build arguments; both must be this variant's repository.
track_image="${TRACK_IMAGE:-ghcr.io/agentux-os/${IMAGE_ID}:latest}"
install_image="${INSTALL_IMAGE:-$track_image}"
[[ "$track_image" =~ ^ghcr\.io/agentux-os/${IMAGE_ID}:[a-z0-9._-]+$ ]] \
    || { echo "TRACK_IMAGE $track_image is not a tag of ghcr.io/agentux-os/${IMAGE_ID}" >&2; exit 1; }
[[ "$install_image" =~ ^ghcr\.io/agentux-os/${IMAGE_ID}(:[a-z0-9._-]+|@sha256:[0-9a-f]{64})$ ]] \
    || { echo "INSTALL_IMAGE $install_image is not ghcr.io/agentux-os/${IMAGE_ID}" >&2; exit 1; }
arch="$(uname -m)"

# /root links to /var/roothome, which an image does not ship; some
# scriptlets write there.
mkdir -p "$(realpath /root)"

case "$arch" in
    x86_64) efi_pkgs=(grub2-efi-x64-cdboot) fallback=fbx64.efi grub=grubx64.efi ;;
    aarch64) efi_pkgs=(grub2-efi-aa64-modules) fallback=fbaa64.efi grub=grubaa64.efi ;;
    *) echo "unsupported architecture $arch" >&2; exit 1 ;;
esac

# anaconda-live is the installer for live media (liveinst); livesys-scripts
# sets up the live user and autologin at boot; dracut-live has the initramfs
# modules that find the ISO and mount its squashfs.
dnf -y install \
    anaconda-live \
    dracut-live \
    livesys-scripts \
    qemu-guest-agent \
    "${efi_pkgs[@]}"
# The desktop note below is Plasma's sticky note widget.
if ! rpm -q --quiet kdeplasma-addons; then
    dnf -y install kdeplasma-addons
fi
dnf clean all

# The initramfs, again (the image's has no live modules), with the AgentUX
# boot splash in it as before.
set -- /usr/lib/modules/*
test "$#" = 1
kver="${1##*/}"
img="/usr/lib/modules/$kver/initramfs.img"
DRACUT_NO_XATTR=1 dracut --no-hostonly --kver "$kver" --reproducible --zstd \
    --add "dmsquash-live dmsquash-live-autooverlay" --force "$img"
lsinitrd "$img" >/tmp/initramfs.txt
grep -q 'dmsquash-live-root' /tmp/initramfs.txt
grep -q 'usr/share/plymouth/themes/agentux/agentux.script$' /tmp/initramfs.txt
rm /tmp/initramfs.txt
chmod 0644 "$img"

# Titanoboa copies /boot/efi/EFI onto the ISO's EFI partition. Fedora keeps
# shim and GRUB under /usr/lib/efi; the fallback loader is replaced with
# GRUB, so firmware that starts EFI/BOOT's shim ends up in GRUB.
mkdir -p /boot/efi
cp -av /usr/lib/efi/*/*/EFI /boot/efi/
cp -v "/boot/efi/EFI/fedora/$grub" "/boot/efi/EFI/BOOT/$fallback"

# GRUB entries and the ISO label for Titanoboa. The label is what the
# initramfs looks for (root=live:CDLABEL=). SELinux is permissive in the
# live session, as in Titanoboa's examples: the squashfs carries no labels.
mkdir -p /usr/lib/bootc-image-builder
cat >/usr/lib/bootc-image-builder/iso.yaml <<EOF
label: "$label"
grub2:
  default: 0
  timeout: 5
  entries:
    - name: "Try or install $title"
      linux: "/images/pxeboot/vmlinuz quiet rhgb root=live:CDLABEL=$label rd.live.image enforcing=0"
      initrd: "/images/pxeboot/initrd.img"
    - name: "Try or install $title (basic graphics)"
      linux: "/images/pxeboot/vmlinuz quiet rhgb root=live:CDLABEL=$label rd.live.image enforcing=0 nomodeset"
      initrd: "/images/pxeboot/initrd.img"
EOF

# The live root is an overlay whose upper layer lives in /run, a small tmpfs;
# give /var/tmp (ostree's scratch space during the install) a larger one.
rm -rf /var/tmp
mkdir -p /var/tmp
cat >/etc/systemd/system/var-tmp.mount <<'EOF'
[Unit]
Description=Larger tmpfs for /var/tmp on the live system

[Mount]
What=tmpfs
Where=/var/tmp
Type=tmpfs
Options=size=50%%,nr_inodes=1m

[Install]
WantedBy=local-fs.target
EOF
systemctl enable var-tmp.mount

rm -f /etc/localtime
systemd-firstboot --timezone UTC

# ---- live session ----------------------------------------------------------

cp -a "$src/files/." /
chmod 0755 /usr/libexec/agentux/live-*
install -D -m 0644 "$src/livesys-session-extra" /var/lib/livesys/livesys-session-extra
printf '%s\n' "$install_image" >/usr/share/agentux/live/install-image
printf '%s\n' "$track_image" >/usr/share/agentux/live/track-image
: >/usr/share/agentux/live/marker

sed -i 's/^livesys_session=.*/livesys_session=kde/' /etc/sysconfig/livesys
grep -qx 'livesys_session=kde' /etc/sysconfig/livesys
systemctl enable livesys.service livesys-late.service
# No first-boot wizard: livesys creates the user. (livesys also marks it
# done at boot; this keeps plasma-setup from starting before that.)
touch /etc/plasma-setup-done

# Login-time downloads: none. The agent CLIs install on demand ("Install the
# agent CLIs" on the desktop starts the unit); the Antigravity ACP server
# (~1 GB unpacked) never runs live, see its drop-in.
systemctl --global disable agentux-first-login.service agentux-antigravity-acp.service
# Nothing to update or mark on a live medium: bootupd's boot-time update
# fails there, and so does GRUB's boot-success flag.
systemctl disable bootloader-update.service
systemctl --global disable grub-boot-success.timer
systemctl --global enable agentux-live-demo.service
test ! -e /etc/systemd/user/default.target.wants/agentux-first-login.service
test ! -e /etc/systemd/user/default.target.wants/agentux-antigravity-acp.service
test -e /etc/systemd/user/default.target.wants/agentuxd.service
grep -q -- '--fake-agents' /usr/lib/systemd/user/agentuxd.service.d/50-agentux-live.conf

# The panel: "Install AgentUX" first, then the AgentUX launchers. The layout
# script runs at the live user's first (and only) login. Then a sticky note
# on the desktop that explains the live session and the demo (its text is
# put in place by livesys-session-extra).
layout=/usr/share/plasma/look-and-feel/os.agentux.desktop/contents/layouts/org.kde.plasma.desktop-layout.js
grep -q '^    "applications:agentux-cockpit.desktop",$' "$layout"
sed -i 's|^    "applications:agentux-cockpit.desktop",$|    "applications:agentux-live-install.desktop",\n&|' "$layout"
cat "$src/layout-live.js" >>"$layout"
grep -q 'agentux-live-install.desktop' "$layout"

# ---- installer -------------------------------------------------------------

# Anaconda's product name comes from /etc/system-release ("AgentUX 44" in
# its title bar instead of Fedora's); a link to fedora-release otherwise.
fedora="$(sed -n 's/^VERSION_ID=//p' /usr/share/agentux/os-release.base | tr -d '"')"
test -n "$fedora"
rm -f /etc/system-release
echo "$title release $fedora" >/etc/system-release

# The web installer's look: anaconda-webui runs in Cockpit and takes its logo
# and brand colours from Cockpit's branding (Fedora's blue title bar and
# logo otherwise). Cockpit looks in branding/<ID>-<VARIANT_ID>/ before
# branding/<ID>/, so this adds AgentUX's (live/cockpit-branding: the mark,
# Ink, Lime and Moss) without touching Fedora's files. The name in the title
# bar is os-release's PRETTY_NAME, already AgentUX's.
branding="/usr/share/cockpit/branding/$ID-$VARIANT_ID"
test -d /usr/share/cockpit/branding/fedora
mkdir -p "$branding"
cp -v "$src"/cockpit-branding/* "$branding/"
test -f "$branding/branding.css" && test -f "$branding/logo.png"

# An Anaconda profile for AgentUX: Kinoite's (Btrfs, the ostree defaults),
# picked by os-release's ID and VARIANT_ID.
mkdir -p /etc/anaconda/profile.d
cat >/etc/anaconda/profile.d/agentux.conf <<EOF
# AgentUX live installer (live ISO only).
[Profile]
profile_id = $IMAGE_ID
base_profile = fedora-kinoite

[Profile Detection]
os_id = $ID
variant_id = $VARIANT_ID
EOF

# What the installer installs (live/install.ks): the signed image from the
# registry, verified against the image's own signature policy, with the
# deployment tracking it like any other install.
sed -e "s|@INSTALL_IMAGE@|$install_image|g" -e "s|@TRACK_IMAGE@|$track_image|g" \
    "$src/install.ks" >/usr/share/agentux/live/install.ks
if grep -q '@' /usr/share/agentux/live/install.ks; then exit 1; fi
test -f /usr/share/anaconda/interactive-defaults.ks
cat >>/usr/share/anaconda/interactive-defaults.ks <<'EOF'

# AgentUX (live ISO): install the published image.
%include /usr/share/agentux/live/install.ks
EOF
cat /usr/share/anaconda/interactive-defaults.ks
cat /etc/sysconfig/qemu-ga 2>/dev/null || true

# Fail here, not at boot, if a piece is missing.
command -v liveinst
test -x /usr/libexec/livesys/livesys-main
command -v qemu-ga
if command -v desktop-file-validate; then
    desktop-file-validate /usr/share/applications/agentux-live-*.desktop
fi
