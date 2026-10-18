# Stable Desktop Media and Unified Offline Installer

**Status:** approved for planning
**Date:** 2026-10-17 (updated 2026-10-18: the Hyprland variant is retired, [ADR 0018](https://github.com/agentux-os/agentux/blob/main/docs/adr/0018-retire-the-hyprland-variant.md), so the media cover Plasma and COSMIC)

## Goal

Provide stable AgentUX downloads for Plasma and COSMIC on `x86_64` and `aarch64`, while making a single offline installer per architecture that lets the user choose which one system to install. Keep each installed desktop in its own signed bootc image and update channel.

## User and business outcome

People should be able to try the desktop they intend to use with a dedicated Live ISO, or install either desktop without internet using one clearly labeled installer ISO for their machine architecture. They should not need to understand image registries, download two installer ISOs, or risk installing a different desktop from the one selected. Stable downloads must remain verifiable and update automatically after an approved release.

## Agreed product shape

- **Four stable Live ISOs:** Plasma and COSMIC, each for `x86_64` and `aarch64`. They remain separate artifacts and boot directly into their named desktop.
- **Two unified offline installer ISOs:** one for `x86_64`, one for `aarch64`. Each contains the two architecture-matched, compressed installation payloads and offers a choice of Plasma or COSMIC.
- The installer expands/writes only the selected payload to the destination disk. Installation must complete without network access. It must not install both desktops into one system.
- Each installed system follows the selected desktop's own signed stable image/channel. Plasma and COSMIC remain independently built, released, signed, and updated.
- Live media compression is not redesigned as part of the installer work. Live ISOs already contain a SquashFS root filesystem. A separate benchmark may evaluate compression settings, but any change must preserve boot performance and reliability and must not combine the two Live environments into one image.

## Approaches considered

1. **One multi-payload offline ISO per architecture (recommended).** Bundle two independently produced and signed image payloads in compressed form; show a desktop selector; verify the selected payload offline; write only that payload. This meets the one-download/offline requirement while keeping installed systems and update streams separate. It adds installer, verification, and capacity complexity.
2. **Keep two installer ISOs per architecture.** Minimal change and simple trust/install flow, but users must choose/download among four installer files, undermining the unified offline-media requirement.
3. **One bootc image containing both desktops.** Simpler payload selection but couples desktop dependencies, updates, storage, and support into one larger installed system. This conflicts with separate desktop variants and is not selected.

## Stable image and release behavior

- Promote `ghcr.io/agentux-os/agentux` and `agentux-cosmic` to version and `:stable` tags only through the existing approved release flow.
- Release candidates are immutable digests. Validate the AgentUX signature and image identity before use in any Live or offline installer build.
- COSMIC becomes stable only after its image, both architectures, live boot/install behavior, rollback, and offline installation payload pass the same release gates. Existing release approval remains mandatory.
- The four Live ISOs are built from the release's exact signed image digests, tested, checksummed, signed, and published with versioned URLs and stable aliases.
- Build the two offline ISOs from the same release candidate digests. Each ISO's catalog records the exact variant, architecture, digest, signature identity, compressed payload size, and checksum for every embedded payload.
- Publish the release metadata only after all four Live ISOs and both installer ISOs, checksums, signatures, and required tests are present. Write `latest.json` last so consumers never observe a partially published release.
- Nightly builds remain separate from stable aliases and metadata.

## Offline installer architecture and trust

- Build two architecture-specific install payloads from the same signed images used by stable release. Compress each payload for storage on ISO; do not recompress or mutate the signed image contents in a way that invalidates image verification.
- Package an installer catalog and detached integrity/signature evidence with the payloads. The installer verifies catalog authenticity, architecture compatibility, digest, and payload integrity offline before enabling installation.
- Present two explicit choices with desktop name, architecture, release version, compressed size, and required target-disk capacity. Default to no selection; never silently choose a desktop.
- Stream/decompress only the selected payload to the target or bounded temporary storage. Do not require both expanded images to fit in RAM or on the target disk simultaneously. Clearly report insufficient disk space, corrupt media, signature failure, or write failure before claiming success.
- After writing, verify the installed deployment's image identity and ensure it tracks the selected variant's `:stable` channel. The installer must not need network to install; networking may be offered after installation for updates.
- Preserve bootability on supported UEFI hardware for both architectures. Keep secure-boot behavior and bootloader ownership explicit and covered by tests.
- Exact payload format and extraction mechanism are an implementation-plan decision informed by a prototype/size benchmark. Do not assume that simply placing two existing installer ISOs inside another ISO is the final design.

## Live ISO behavior and size optimization

- Keep one Live ISO per variant and architecture: four stable artifacts total. Each image contains only its own desktop and its own matching network installer target.
- The current Live build uses Titanoboa to produce a SquashFS-backed bootable ISO; the initramfs is separately rebuilt with Zstandard. A whole-file compression pass alone is not considered a useful ISO optimization because users need bootable media.
- Measure existing artifact sizes and boot time as the baseline. Any change to SquashFS compressor, block size, or compression level must compare output size, boot-to-desktop time, CPU/RAM use during boot, and read latency on both architectures.
- Adopt a Live compression change only if the saved download size is material and boot reliability/performance remains within an agreed regression budget. Otherwise retain the current per-variant Live media unchanged.
- Do not create a multi-desktop Live ISO in this scope; it would duplicate two root filesystems and could increase download size without reliable cross-image deduplication.

## Website and metadata

- The download page presents stable Live downloads by desktop and architecture, and one unified offline installer download per architecture.
- Use signed `latest.json` records for version, URL, size, SHA-256, variant, architecture, media kind, stable channel, and truthful boot/install test coverage. Live records identify their exact variant; installer records identify the set of included variants and payload catalog version.
- Keep direct stable aliases for the four Live ISOs and two installers. Retain version-pinned URLs and checksums for reproducibility.
- If metadata is unavailable or malformed, the page keeps safe fallback links and does not hide existing downloads.
- Document that Live installation requires network, while the unified installer is fully offline; identify supported architecture and firmware limits without implying certification of every ARM board.

## Validation and acceptance criteria

1. Image and release contract tests prove both variant digests are resolved, signature-verified, architecture-matched, and promoted only after approval.
2. Build all four Live ISOs from the release digests. Boot each architecture/variant where runner capability permits; tests must verify desktop identity, demo, installer target, stable tracking channel, and checksum/signature. An architecture without sufficient VM support must be reported as build-only and cannot silently be labeled boot-tested.
3. For each architecture, build one offline ISO containing exactly the two matching payloads and catalog records. Inspect its contents and prove it has no network dependency during installation.
4. VM tests exercise both selections on each architecture where practical, and at minimum a complete unattended install for every variant on x86_64 plus ARM boot/install tests via KVM or TCG. Verify the selected image/channel after reboot and prove the other two variants were not installed.
5. Negative installer tests cover altered catalog, wrong architecture, corrupted/truncated payload, invalid/missing signature, insufficient target capacity, and interrupted write. Fail closed without reporting a successful install.
6. Benchmark compressed payload and ISO sizes against the current per-variant installer baseline. Record compression ratio, build time, peak disk usage, RAM, and install time. The offline ISO must be materially smaller than the sum of the two current per-variant installer ISOs; the exact acceptance threshold is set from the prototype before implementation is considered complete.
7. Live compression benchmarks compare each candidate to the current SquashFS baseline on x86_64 and aarch64. No Live compressor change ships without material size savings and acceptable boot performance.
8. Publisher tests prove all six media artifacts, checksums, signatures, and release metadata are complete before aliases or `latest.json` are updated.
9. Website tests verify all four Live choices and two installer choices, architecture labels, sizes/checksums, stable status, offline-vs-online descriptions, and safe metadata fallback.
10. Existing Plasma image, Live, installer, release, signature, rollback, and website contract tests remain green.

## Out of scope

- Installing multiple desktop environments into one deployed system.
- Combining the two environments into a single Live ISO.
- Replacing or relaxing the existing release approval and signature policy.
- Publishing new stable artifacts as part of implementation; a qualifying versioned release and approval publish them.
- Certifying individual physical ARM boards, firmware, GPUs, or peripherals.
- A guaranteed ISO-size number before the payload-format prototype and benchmark.

## Operational risks

- Two compressed payloads may still make the unified installer several gigabytes; the prototype must measure real release images before committing to capacity requirements.
- Offline authenticity is a hard requirement: a checksum stored beside an untrusted payload is insufficient. The trusted catalog/signature verification path must work without network and fail closed.
- Decompression, disk writing, and post-write verification need careful recovery behavior for power loss and media errors.
- ARM TCG can make installation tests slow. Timeouts and evidence collection must be explicit; build success is not equivalent to boot/install validation.
- Stable alias and metadata publication must remain atomic across six artifacts.
