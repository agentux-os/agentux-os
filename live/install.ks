# AgentUX live installer: what Anaconda installs from the live session
# (live/build.sh puts this in /usr/share/agentux/live/install.ks, with the
# image of the live system's variant, and %includes it from Anaconda's
# interactive defaults). Everything else, disk, language, time zone and
# account, is asked for interactively.
#
# The image comes from the registry, not from the live system, so nothing
# live-only ends up installed. No --no-signature-verification: the pull goes
# through the live system's /etc/containers/policy.json, which is the image's
# own and requires the AgentUX cosign signature for this repository, so an
# unsigned or tampered image fails the install.
ostreecontainer --url=@INSTALL_IMAGE@ --transport=registry

# Track the image for updates the way bootc-image-builder's installer ISO
# does (so `bootc upgrade` follows :latest and checks the policy on every
# pull), and leave a marker for automated tests on the serial console.
%post --erroronfail
set -e
bootc switch --mutate-in-place --transport registry @INSTALL_IMAGE@
if [ -c /dev/ttyS0 ]; then
    echo "AgentUX install finished" >/dev/ttyS0 || true
fi
%end
