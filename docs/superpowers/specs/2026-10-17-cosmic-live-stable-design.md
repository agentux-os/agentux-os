# COSMIC Stable Image and Live ISO Design

## Goal

Make COSMIC a supported stable AgentUX image and publish COSMIC Live ISOs for both `x86_64` and `aarch64` through the existing approved-release pipeline.

## User and business outcome

People choosing COSMIC should be able to download a tested Live ISO, install AgentUX from that session, and receive signed updates from the COSMIC `:stable` channel. The website and release metadata must clearly distinguish stable artifacts from nightly builds and update automatically after each approved release.

## Scope

- Promote the already-built and signed `ghcr.io/agentux-os/agentux-cosmic` image to `:<version>` and `:stable` only after its candidate digest passes the release gates and the existing release approval.
- Build and publish only COSMIC Live ISOs, for both `x86_64` and `aarch64`. Do not add an offline installer ISO for COSMIC.
- Gate release publication on successful COSMIC live-session and installation tests for both architectures.
- Use QEMU/KVM for `x86_64`. When the ARM runner lacks KVM, use QEMU system emulation with TCG and UEFI for `aarch64`; the test must reach the COSMIC live session and complete the installation checks. This validates the virtual platform, not every physical ARM board.
- Publish versioned and stable ISO aliases with SHA-256 checksums and AgentUX-key signatures. Add the COSMIC image and ISO records to signed `latest.json`.
- Update the download page so it presents COSMIC as stable after metadata advertises it, while retaining the nightly link as a fallback before the first stable release.
- Update operator/user documentation and release notes to describe COSMIC Stable as Live-only and multi-architecture.

## Release and trust flow

1. `build.yml` continues to build, smoke-test, sign and publish the COSMIC image for both architectures on `main`. A release does not rebuild the image.
2. `release.yml` resolves the tagged commit's immutable `sha-<commit>` COSMIC image, verifies the AgentUX key and GitHub Actions keyless signatures, and exposes that digest to downstream jobs.
3. A COSMIC Live job builds both architectures from that exact digest and sets the installed system's tracking channel to `agentux-cosmic:stable`. Release-tag channel selection must reject a mutable or mismatched image reference.
4. Both architecture tests must pass before the release job can proceed. The existing release environment approval remains the only step allowed to move image tags or publish stable downloads.
5. After approval, the release job promotes the verified COSMIC digest to `:<version>` and `:stable`, then publishes both tested Live ISOs. Missing either ISO, checksum, or signature must fail publication before `latest.json` is replaced.
6. `latest.json` is written last and includes `images.cosmic` plus both COSMIC Live ISO records (`variant: cosmic`, `kind: live`, `channel: stable`). It reports boot and installation test coverage accurately for every ISO.

Nightly `:latest` images and `iso/nightly/` artifacts remain independent and continue to move on the existing nightly schedule/dispatch. COSMIC remains absent from stable metadata until the first qualifying release is approved and published.

## Architecture test and user-facing status

The ARM runner currently may lack `/dev/kvm`, and the live VM harness currently requires KVM. Extend the harness to support an explicit TCG mode for the ARM release test, selecting an AArch64 UEFI `virt` machine and a TCG-compatible CPU rather than `-cpu host`. Keep KVM as the x86_64 path. Do not silently turn an ARM test into a build-only success for a stable release.

The release notes and download page must not imply physical-board certification. They may say the artifact booted and installed in CI/VM; the supported hardware scope remains Fedora-supported UEFI systems described by the project documentation.

Add separate `boot_tested` and `install_tested` metadata so the website can distinguish “booted and installed in CI”, “booted in CI; install not tested”, and “built but not boot-tested”. For this COSMIC stable gate both flags must be true for both architectures.

## Website behavior

- Before a stable COSMIC record exists, the COSMIC tab remains marked experimental/nightly and its URLs target `iso/nightly/`.
- When `latest.json` contains stable COSMIC image and Live ISO records, the tab changes to a stable label, selects each architecture's stable URL, checksum URL, size and test status from metadata.
- If metadata cannot be fetched, the page remains usable with its current safe fallback links; no JavaScript failure may hide Plasma or prevent downloads.

## Out of scope

- COSMIC offline installer ISO.
- Stable COSMIC release publication during this implementation. The change prepares the pipeline; a later version tag, successful gates and release approval are required to publish.
- Certification of specific physical ARM models or peripherals.
- Changes to Plasma/Hyprland stable policy, release cadence, or COSMIC nightly behavior beyond truthful shared metadata.

## Acceptance criteria

- Contract tests prove the release resolves/verifies the COSMIC digest, builds Live ISOs for both architectures from that digest, waits for both test jobs, promotes the COSMIC image only after approval, and requires both COSMIC ISO names before publication.
- Tests prove the release channel script accepts COSMIC stable only for a valid tagged digest and does not alter nightly behavior.
- VM-harness tests cover KVM and ARM TCG selection; the release configuration cannot skip ARM boot/install tests and still succeed.
- Publisher tests prove both architecture artifacts, checksums, signatures, COSMIC image metadata and ISO metadata are present before `latest.json` publication.
- Website tests prove nightly fallback and metadata-driven stable COSMIC links/statuses, while preserving the Plasma and installer links.
- Repository contract tests pass, the website builds, and the website download-page contract passes.

## Operational caveats

- ARM TCG may make full installation testing materially slower than KVM; keep the release job timeout explicit and collect logs/screenshots as artifacts on failure.
- QEMU `virt` tests do not prove compatibility with every ARM board. Report the VM scope precisely and collect real-hardware reports after release.
- Stable promotion is atomic at the existing release-job boundary: an unapproved, rejected, or failed release must leave `:stable`, stable ISO aliases, and `latest.json` unchanged.
