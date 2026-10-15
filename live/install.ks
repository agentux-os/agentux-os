# AgentUX live installer: what Anaconda installs from the live session
# (live/build.sh puts this in /usr/share/agentux/live/install.ks, with the
# images of the live system's variant, and %includes it from Anaconda's
# interactive defaults). @INSTALL_IMAGE@ is what gets pulled: the channel's
# tag, or for a release ISO the release's digest, so it installs exactly what
# was tested and released. @TRACK_IMAGE@ is the channel the installed system
# follows: ghcr.io/agentux-os/<image>:stable (release ISOs) or :latest. Language, keyboard and disk are asked for
# interactively; the account is created by plasma-setup's first-boot wizard.
#
# The image comes from the registry, not from the live system, so nothing
# live-only ends up installed. No --no-signature-verification: the pull goes
# through the live system's /etc/containers/policy.json, which is the image's
# own and requires the AgentUX cosign signature for this repository, so an
# unsigned or tampered image fails the install.
ostreecontainer --url=@INSTALL_IMAGE@ --transport=registry

# Track the channel for updates the way bootc-image-builder's installer ISO
# does (so `bootc upgrade` follows it and checks the policy on every pull),
# and leave a marker for automated tests on the serial console.
%post --erroronfail
set -e
bootc switch --mutate-in-place --transport registry @TRACK_IMAGE@
# The profile selector may provide AGENTUX_PROFILE in a future branded
# installer flow. Keep the seed optional so offline/base installs behave as
# they do today; first boot applies it through agentux-profile-apply.service.
if [ -n "${AGENTUX_PROFILE:-}" ] && command -v agentux >/dev/null 2>&1; then
    agentux profile seed "$AGENTUX_PROFILE"
fi
# Anaconda writes the root file system into /etc/fstab (btrfs, with
# subvol=root and its mount options). On a bootc system / is a composefs
# overlay that the initramfs mounts from the kernel command line (root=,
# rootflags=), so systemd-remount-fs fails at every boot trying to apply
# those options to it ("overlay: No changes allowed in reconfigure") and the
# system starts degraded. bootc's own installer writes no such line; this
# comments it out. The other entries (/boot, /boot/efi) stay.
if [ -f /etc/fstab ]; then
    awk '$2 == "/" && $1 !~ /^#/ {print "# " $0 "    # disabled by the AgentUX installer: ostree mounts /"; next} {print}' \
        /etc/fstab >/etc/fstab.agentux
    cat /etc/fstab.agentux >/etc/fstab
    rm -f /etc/fstab.agentux
fi
if [ -c /dev/ttyS0 ]; then
    echo "AgentUX install finished" >/dev/ttyS0 || true
fi
%end
