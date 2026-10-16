# AgentUX COSMIC Live ISO

**Status:** design for review
**Date:** 2026-10-16

## Goal

Offer two separate AgentUX Live ISO choices: the existing KDE Plasma experience and a new COSMIC experience. The COSMIC option must boot into an AgentUX-branded COSMIC session, run the same Cockpit and fake-agent demo, and preserve the Live ISO's network-based installation flow.

The existing offline installer ISO remains unchanged and does not gain a COSMIC selection or COSMIC payload in this scope. The COSMIC live installer, when used, installs the COSMIC AgentUX image from the registry; it must not install KDE by mistake. The live environment must clearly disclose that installation requires a network connection.

## Approaches

1. **Separate COSMIC system image and Live ISO (recommended).** Build and sign `ghcr.io/agentux-os/agentux-cosmic` as its own bootc image, then build a COSMIC Live ISO from it. The image contains COSMIC and shared AgentUX components, but not Plasma. This keeps the performance comparison meaningful and keeps the installed system's desktop unambiguous.
2. **Install COSMIC beside Plasma in the current image.** Build a second session into the existing Plasma image and select it at live boot. This reuses more of the present build but retains both desktops and their services, increases image/runtime cost, and makes it harder to tell whether COSMIC is genuinely leaner. Do not use this for the COSMIC edition.
3. **Use Fedora's COSMIC Atomic image as the AgentUX COSMIC image base.** This retains a separately signed AgentUX image and matching install/update flow while avoiding a duplicated COSMIC package set. Adopt this approach for the COSMIC image only; Plasma and Hyprland remain unchanged.

## Image and desktop boundaries

- Keep the existing Plasma image and its behavior intact.
- Add a `cosmic` image variant based on Fedora's COSMIC Atomic bootable-container image for Fedora 44. Resolve the nightly tag to an architecture-specific immutable digest per CI job, validate the expected COSMIC session and first-setup entry point, and record each digest in the job summary. The upstream Quay images have a four-week blob-retention window, so do not check their digests into long-lived workflow configuration. Do not duplicate their package set in AgentUX. This is a community-built upstream image and remains nightly-only; source signature verification is not asserted by this change.
- Install the shared AgentUX Core and Cockpit packages in both images. The COSMIC image must not install the Plasma-specific AgentUX overlay. Add a COSMIC-specific defaults/configuration layer in `agentux-desktop`, alongside (not inside) the existing Plasma overlay.
- Keep setup catalog/backend behavior shared where it is desktop-independent. Provide the COSMIC session with the AgentUX Welcome/Cockpit first-run launch behavior and AgentUX branding without depending on Plasma-only autostart, panel, or setup mechanisms. Use Fedora COSMIC's supported initial account setup for installed systems; the live session continues to use the existing live-user flow.
- The COSMIC Live ISO starts COSMIC by default. The Plasma Live ISO continues to start Plasma; the existing Hyprland live option remains unchanged.

## Live install and release behavior

- Extend the existing image build, signature verification, release promotion, and Live ISO workflows for the COSMIC image. Publish and sign the image under its own repository; add that repository to the image's signature policy and test the policy against signed and unsigned examples.
- Build separate COSMIC Live ISO artifacts for x86_64 and aarch64 using the same live-session design and AgentUX demo as Plasma. The live installer targets the COSMIC image and its matching update channel/digest, just as each current live variant targets its own image.
- Do not build a COSMIC offline installer ISO, change the default offline installer, or put both desktop images into one ISO in this project.
- Keep artifact names and download-page labels explicit, for example `agentux-cosmic-live-<version>-<arch>.iso`, so users can distinguish the two live choices before download.
- COSMIC can be offered on the normal stable channel only after its release image, live install, rollback, and supported-architecture checks pass. Until then it is available from nightly builds only.

## Validation and launch criteria

1. Build the COSMIC bootc image natively for x86_64 and aarch64; verify expected desktop/session packages and absence of the Plasma session and Plasma AgentUX overlay.
2. Verify image signature enforcement for the new repository and ensure the existing Plasma signature and update flow is unchanged.
3. Boot each COSMIC Live ISO and verify the live user reaches COSMIC, Cockpit opens, the fake-agent demo is visible, agentuxd runs in fake mode, and no first-login downloads or persistent-disk writes occur before installation.
4. On the x86_64 test VM, install from the COSMIC Live ISO using its network installer, reboot the installed system, and verify COSMIC, the AgentUX Welcome/Cockpit flow, Core services, the selected update channel, and rollback behavior. The install must never land on the Plasma image.
5. Keep the existing Plasma and Hyprland Live ISO checks passing. Build ARM64 artifacts; run equivalent boot/install checks where the runner supports them and report any architecture-specific gap explicitly.
6. Compare Plasma and COSMIC idle memory, CPU, login-to-interactive time, and basic interaction latency on the same VM/hardware configuration. Capture the VM graphics renderer and settings. Do not advertise COSMIC as lighter unless measurements show a repeatable improvement; VM-only results must be labeled as such.
7. Review screenshots of both live desktops and update download documentation with separate choices, architecture availability, network-install behavior, and COSMIC's initial support status.

## Out of scope

- Replacing Plasma as the default or removing its Live ISO.
- Adding COSMIC to the offline installer ISO or offering a desktop picker in that installer.
- Installing both desktop environments in one AgentUX image.
- Changing Core's agent orchestration, the Cockpit's product behavior, or the AgentUX programming language.
- Claiming a performance win based on language choice or a single VirtualBox run.

## References

- Current AgentUX image and variants: [`Containerfile`](../../../Containerfile).
- Current offline installer workflow: [`.github/workflows/iso.yml`](../../../.github/workflows/iso.yml).
- Current Live ISO workflow: [`.github/workflows/live.yml`](../../../.github/workflows/live.yml).
- Fedora COSMIC Atomic release and architectures: <https://fedoraproject.org/atomic-desktops/cosmic/download/>.
- Fedora COSMIC Atomic package manifest: <https://gitlab.com/fedora/ostree/ci-test/-/raw/main/packages/cosmic-atomic.yaml>.
- Fedora COSMIC Atomic shared manifest: <https://gitlab.com/fedora/ostree/ci-test/-/raw/main/cosmic-atomic-common.yaml>.
