# Stable Desktop Media Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish four stable per-desktop Live ISOs and two architecture-specific offline installer ISOs that install exactly one of Plasma or COSMIC.

**Architecture:** Keep the two bootc images and update channels independent. Build one compressed, authenticity-verifiable payload per image and architecture, package the two matching payloads into one offline installer for each architecture, and make the chosen payload available to the existing Anaconda/bootc installation flow. Extend the approved-release and download metadata pipeline atomically; keep Live ISOs separate and benchmark any Live SquashFS changes independently.

**Tech Stack:** Fedora bootc, Anaconda / bootc-image-builder, Podman and Skopeo, Cosign, SquashFS/Titanoboa, GitHub Actions, Bash, Node.js contract tests, Astro website.

**Spec:** [`docs/superpowers/specs/2026-10-17-stable-desktop-media-design.md`](../specs/2026-10-17-stable-desktop-media-design.md)

## Global Constraints

- Publish exactly four stable Live ISOs: Plasma and COSMIC for `x86_64` and `aarch64`.
- Publish exactly two unified offline installers: one for `x86_64` and one for `aarch64`; each contains exactly the two matching architecture payloads.
- Installation is offline-capable and installs only the explicitly selected environment; never silently default the desktop selection.
- Preserve separate signed bootc images, stable channels, release tags, and rollback behavior for the two variants.
- Verify the selected payload's authenticity and architecture offline before enabling the install; fail closed on invalid/missing evidence.
- Build release artifacts from immutable candidate digests and publish stable aliases only after the existing release approval.
- Write `latest.json` only after all six media artifacts, checksums, signatures, and required validation are present.
- Keep Live media separate; only ship compression changes that materially reduce size without unacceptable boot regressions.
- ARM VM/build coverage must be reported accurately; build-only is never represented as boot/install-tested.

## Review Focus

- **Tampered payload/catalog:** installer rejects it offline before disk writes; test altered signature, catalog and payload digest.
- **Architecture mismatch:** installer rejects payloads for the wrong CPU architecture; test cross-architecture catalog entries.
- **No selection / invalid choice:** installer makes no destructive change and requires explicit valid selection; test absent, malformed and unsupported variant.
- **Low capacity / interrupted write:** installer reports failure and does not claim success; test capacity preflight and simulated write failure.
- **Incomplete release artifact set:** publication leaves stable aliases and `latest.json` unchanged; test missing each required media/checksum/signature class.

---

## Repository and File Map

AgentUX OS repository (this worktree):

- `.github/workflows/build.yml`, `.github/workflows/release.yml`, `.github/workflows/live.yml`, `.github/workflows/iso.yml`: image/release/live/installer job graph and artifact gates.
- `.github/scripts/channel.sh`, `.github/scripts/publish-iso.sh`: variant channel policy, artifact validation, signed publication, release notes and `latest.json` generation.
- `disk_config/iso.toml`, `installer/brand-iso.sh`, `installer/product/`: existing Anaconda installer configuration and ISO branding.
- New `installer/offline/`: payload catalog/packing and installer-side validation/loading helpers; exact transport is fixed by Task 1 before implementation.
- `tests/`: add offline-payload/catalog/installer contracts and VM scenarios; extend current COSMIC/release/ISO tests.
- `README.md`: stable Live and unified offline downloads, install choices, verification, and architecture coverage.

Website repository (existing isolated worktree `C:\Users\wende\Projects\agentux-os\.worktrees\cosmic-live-stable-download`):

- `src/pages/download.astro`: stable variant and architecture choices, offline installer choices and metadata rendering.
- `tests/download-page.mjs`: download metadata, fallback, and presentation contracts.

## Task 1: Prove the Offline Payload and Installer Transport

**Files:**
- Inspect: `.github/workflows/iso.yml`, `disk_config/iso.toml`, `installer/brand-iso.sh`, `tests/iso-vm.sh`, `live/install.ks`
- Create: `docs/superpowers/plans/evidence/2026-10-17-offline-payload-prototype.md` (benchmark/evidence only; do not add production implementation)

**Interfaces:**
- Produces a go/no-go decision and the exact payload format, offline verification method, and Anaconda handoff consumed by Tasks 2–4.
- Must compare the lowest-complexity viable bootc-image-builder/Anaconda integration against a compressed OCI archive plus local installer handoff; do not assume `podman load` alone makes Anaconda's `ostreecontainer` source local.

- [ ] **Step 1: Record current baselines.** Capture the published per-variant installer sizes, native build disk usage, and current x86_64 install test procedure. Use `latest.json` and the existing CI build summary; label unbuilt estimates as estimates.
- [ ] **Step 2: Test format feasibility with signed release-like images.** Demonstrate export, compression, offline integrity/signature verification, local Anaconda/bootc consumption, and install to a throwaway VM disk without network.
- [ ] **Step 3: Measure both architectures or document the exact arm64 limitation.** Record compressed size per variant, combined ISO estimate/build result, peak disk/RAM, compression/decompression time, and install time.
- [ ] **Step 4: Write a go/no-go report.** Choose a format only if it preserves image provenance, works offline, installs exactly one image, and fits CI runner capacity. If no candidate satisfies these criteria, stop and return to design review; do not weaken signature or offline requirements.

## Task 2: Implement the Payload Catalog, Packing, and Offline Verification

**Files:**
- Create: `installer/offline/catalog.schema.json`
- Create: `installer/offline/pack-payloads.sh` (or the exact helper name selected by Task 1)
- Create: `installer/offline/verify-payload.sh`
- Create: `tests/offline-payload-contract.mjs`
- Modify: `.github/workflows/build.yml` only if a reusable signed payload output is needed by Tasks 3 and 6

**Interfaces:**
- `pack-payloads.sh CATALOG_DIR OUTPUT_DIR ARCH VERSION VARIANT=IMAGE_REF...` emits two payload files and a deterministic catalog for one architecture.
- Catalog fields: schema version, release version, architecture, variant ID, OCI image digest, original image-signature identity, payload filename, compressed byte size, compressed SHA-256, and detached AgentUX media-signature bundle reference.
- `verify-payload.sh CATALOG PAYLOAD PUBLIC_KEY EXPECTED_ARCH EXPECTED_VARIANT` exits zero only when catalog and payload signatures, hashes, architecture, variant, and image digest all match.
- Exact on-disk format and signature commands must follow Task 1's evidence; the catalog must not claim registry-signature verification unless that verification is reproducible offline.

- [ ] **Step 1: Add failing contract tests.** Assert exact two variants, unique payload paths, required catalog fields, deterministic ordering, correct arch/version binding, no untrusted shell evaluation, and signature/hashes checked before extract/load.
- [ ] **Step 2: Run `node tests/offline-payload-contract.mjs` and confirm it fails for missing helper/schema behavior.**
- [ ] **Step 3: Implement the catalog schema and packer.** Reject missing variants, duplicate variant IDs, mutable/non-digest image refs in release mode, cross-architecture images, and absent signature evidence.
- [ ] **Step 4: Add negative verification tests.** Cover altered catalog, corrupt/truncated payload, missing or invalid signature, wrong architecture, wrong variant and path traversal in catalog filenames.
- [ ] **Step 5: Implement offline verifier and rerun `node tests/offline-payload-contract.mjs`.** Expected: all positive and negative contracts pass; invalid inputs fail closed before extraction.
- [ ] **Step 6: Commit the payload catalog and tooling.**

## Task 3: Add Explicit Environment Selection to the Offline Installer

**Files:**
- Modify: `disk_config/iso.toml`
- Modify: `installer/brand-iso.sh` and/or `installer/product/` for clear AgentUX selection presentation where required
- Create: installer selection/load scripts under `installer/offline/`
- Create: `tests/offline-installer-contract.mjs`
- Modify: `tests/iso-vm.sh` to select and assert each environment

**Interfaces:**
- The installer exposes exactly `plasma` and `cosmic` as choices and maps each choice only to a catalog-validated payload for the running architecture.
- Selection begins unset. Invalid/missing selection, verification failure, insufficient target capacity, or payload load failure prevents partition/write/install actions.
- The selected payload is streamed/decompressed only as needed; neither all payloads nor all expanded images may be loaded into RAM or copied to the target.
- After install, the existing bootc provisioning path sets the selected variant's `:stable` reference and verifies the installed image identity.

- [ ] **Step 1: Add failing selection tests.** Assert no default choice, two explicit entries, exact variant-to-payload mapping, wrong-arch rejection, and no disk-write call before selection and verification.
- [ ] **Step 2: Run `node tests/offline-installer-contract.mjs` and confirm the new selection contract fails.**
- [ ] **Step 3: Implement the selection-to-local-image handoff using Task 1's proven Anaconda/bootc transport.** Keep disk partitioning, user setup and branding behavior from the existing installer unless the selected handoff requires a tested change.
- [ ] **Step 4: Add tests for capacity preflight, corrupt media, interrupted extraction/write, no network calls, and correct post-install stable reference.**
- [ ] **Step 5: Run `node tests/offline-installer-contract.mjs` and the installer-specific unit/contracts.** Expected: selected variant maps to one image and failure paths never report success.
- [ ] **Step 6: Commit the interactive offline installer flow.**

## Task 4: Build and Boot-Test the Two Unified Offline ISOs

**Files:**
- Modify: `.github/workflows/iso.yml` (produce one multi-variant ISO per architecture, not one installer per variant)
- Modify: `installer/brand-iso.sh` if media naming/metadata requires it
- Modify: `tests/iso-vm.sh`
- Create: `tests/offline-installer-vm.sh` if separate scenarios improve isolation

**Interfaces:**
- Artifact names: `agentux-offline-<version>-x86_64.iso` and `agentux-offline-<version>-aarch64.iso`; nightly names use the same prefix and existing channel conventions.
- Each ISO includes exactly the two matching architecture payloads, one signed catalog, checksums, and offline verification material.
- VM scenarios accept the ISO path and an explicit variant; they install with networking disabled and verify the selected image ID/channel after reboot.

- [ ] **Step 1: Add failing build-contract tests.** Assert exactly one offline artifact per architecture and two same-arch payloads in the catalog; no per-variant stable installer artifact is required.
- [ ] **Step 2: Implement ISO assembly and artifact naming.** Keep the existing installer boot/branding contract and include catalog/payload files at a stable, documented media path.
- [ ] **Step 3: Add an x86_64 offline install VM test for each variant.** Assert networking is disabled, disk writes begin only after selection and verification, and reboot reports only the selected AgentUX image/channel.
- [ ] **Step 4: Add aarch64 boot/install validation with KVM or TCG where the runner supports it; otherwise report build-only and retain the gap as a release gate per the spec.**
- [ ] **Step 5: Benchmark size/build disk usage against two current per-variant installer ISOs; write measured results into the evidence report and fail if the selected runner cannot safely build the artifacts.**
- [ ] **Step 6: Run the existing installer visual test and VM tests.** Expected: branded selection UI is legible, offline install completes, and existing partition/account/boot contracts remain intact.
- [ ] **Step 7: Commit the two-architecture offline ISO pipeline.**

## Task 5: Promote COSMIC and Build Four Stable Live ISOs

**Files:**
- Modify: `.github/scripts/channel.sh`
- Modify: `.github/workflows/release.yml`
- Modify: `.github/workflows/live.yml`
- Modify: `tests/cosmic-contract.mjs`
- Modify: `tests/release-workflow-contract.mjs`
- Modify: `tests/live-vm.sh` only if aarch64 TCG support is needed for mandatory stable coverage

**Interfaces:**
- Release candidate outputs include immutable digests for `plasma` and `cosmic`.
- Four Live job artifacts use explicit names: `agentux-live` and `agentux-cosmic-live`, each for `x86_64` and `aarch64`.
- A release Live image reference is always the matching candidate digest; installed systems track only that variant's `:stable` channel.

- [ ] **Step 1: Update failing COSMIC/release contracts.** Replace the nightly-only expectations and assert two candidates, four Live jobs/artifacts, matching digests, all test dependencies, and approval before stable promotion.
- [ ] **Step 2: Run `node tests/cosmic-contract.mjs` and `node tests/release-workflow-contract.mjs` to verify they fail on the current COSMIC stable gate.**
- [ ] **Step 3: Enable COSMIC stable in the channel selector only for valid tagged digest releases; keep nightly dispatch behavior unchanged.**
- [ ] **Step 4: Extend `release.yml` to verify/promote the COSMIC image and wait for required Live and offline ISO jobs before publishing.**
- [ ] **Step 5: Add/adjust x86_64 KVM and aarch64 TCG validation.** Tests must identify the desktop and installed target; no ARM build-only job is described as boot-tested.
- [ ] **Step 6: Run the contract tests and available VM tests.** Expected: both stable Live variants build for both architectures and no failed/unsigned candidate reaches promotion.
- [ ] **Step 7: Commit the stable COSMIC and Live release gates.**

## Task 6: Publish Six Artifacts and Machine-Readable Metadata Atomically

**Files:**
- Modify: `.github/scripts/publish-iso.sh`
- Modify: `.github/workflows/release.yml`
- Modify: `.github/workflows/iso.yml`, `.github/workflows/live.yml` artifact download/publish handoff as needed
- Create or modify: `tests/publish-iso-contract.mjs`
- Modify: `tests/release-workflow-contract.mjs`

**Interfaces:**
- Release publisher requires four Live artifacts and two offline installers; each has checksum and AgentUX signature bundle before any stable alias is changed.
- `latest.json` includes records for each media artifact plus image metadata for both variants. Live records identify one `variant`; offline records identify `variants: [plasma, cosmic]` and catalog schema version.
- Installer metadata includes payload sizes/digests and honest test coverage. Website must not infer `boot_tested`/`install_tested` when evidence is missing.

- [ ] **Step 1: Add failing publisher tests.** Missing any artifact, checksum, signature, catalog, or image digest must fail before alias writes or metadata upload.
- [ ] **Step 2: Run `node tests/publish-iso-contract.mjs` to confirm the current publisher accepts an incomplete multi-variant release or lacks these records.**
- [ ] **Step 3: Implement validation, stable/versioned naming, signed SHA256SUMS, release notes, and all six artifact records.** Preserve existing rollback-safe ordering; write `latest.json` last.
- [ ] **Step 4: Add a fixture-based publisher test for all six good artifacts and every missing-artifact/signature case.**
- [ ] **Step 5: Run publisher and release contract tests.** Expected: success fixture publishes correct metadata; every incomplete fixture exits before modifying aliases.
- [ ] **Step 6: Commit metadata and release publication changes.**

## Task 7: Update Downloads, Documentation, and User Guidance

**Files:**
- Website worktree: modify `src/pages/download.astro`
- Website worktree: modify `tests/download-page.mjs`
- OS repository: modify `README.md` and release notes generation in `.github/scripts/publish-iso.sh`

**Interfaces:**
- Website groups four Live downloads by desktop and architecture and exposes two unified offline installer downloads by architecture.
- Stable links, version, sizes, checksums, architecture, and test status come from validated `latest.json`; safe static fallbacks remain available.
- Copy explains Live install needs internet and offline installer does not; selection installs only one desktop and subsequent updates use that desktop's stable channel.

- [ ] **Step 1: Add failing page tests** for all four Live choices, two installers, COSMIC stable state, payload variants, checksums, offline wording, malformed/missing metadata fallback, and no hidden existing Plasma choices.
- [ ] **Step 2: Run `node tests/download-page.mjs` and confirm the new stable/offline assertions fail.**
- [ ] **Step 3: Implement metadata-driven download cards and truthful architecture/test labels in the website worktree.**
- [ ] **Step 4: Run `node tests/download-page.mjs` and `npm run build` in the website worktree.** Expected: page tests and Astro build pass.
- [ ] **Step 5: Update OS README install/download sections and generated release notes; run `node tests/release-workflow-contract.mjs`.**
- [ ] **Step 6: Commit website and OS documentation changes separately in their respective repositories.**

## Task 8: Benchmark Live Compression Without Changing the Media Layout

**Files:**
- Modify: `.github/workflows/live.yml` only if adding a reproducible benchmark job is appropriate
- Modify: `live/Containerfile` / Titanoboa invocation only for a candidate proven by the benchmark
- Create: `tests/live-compression-contract.mjs` if a compression parameter is introduced
- Update: the evidence report from Task 1 with measured baseline/candidate data

**Interfaces:**
- Candidate changes are limited to SquashFS compression/block settings; the four-ISO layout and per-variant image identity do not change.
- Results record ISO bytes, squashfs bytes, build time, boot-to-desktop time, CPU/RAM, and read latency on both architectures where measurable.

- [ ] **Step 1: Capture baseline for Plasma and COSMIC on x86_64 and aarch64 from equivalent builds.**
- [ ] **Step 2: Compare supported SquashFS compressor/level candidates with repeatable measurements.**
- [ ] **Step 3: If no candidate produces material savings within the agreed boot regression budget, record “no change” and do not modify production compression.**
- [ ] **Step 4: If adopting a candidate, add a failing contract test for its explicit parameters, implement the smallest workflow change, and run all four Live boot tests.**
- [ ] **Step 5: Commit benchmark outcome; do not make a speculative compression change.**

## Task 9: Full Verification and Handoff

**Files:**
- No new product files; update the evidence report and plan checkboxes.

- [ ] **Step 1: Run OS contract suite:** `node tests/cosmic-contract.mjs`, `node tests/release-workflow-contract.mjs`, `node tests/build-workflow-contract.mjs`, new offline payload/installer/publisher contracts, `node tests/live-desktop-contract.mjs` where shell support exists, and `git diff --check`.
- [ ] **Step 2: Run `go test ./...` and `go vet ./...` if Go code was changed; run `tests/sigpolicy.sh` and image smoke/boot tests for all release variants.**
- [ ] **Step 3: Run four Live builds/available boot tests and both offline installer VM tests; attach all run summaries and clearly disclose any aarch64 TCG limitation.**
- [ ] **Step 4: Run website download-page test and `npm run build` in the website worktree.**
- [ ] **Step 5: Audit stable publication ordering, six-media checksums/signatures, `latest.json` schema, and that no real release tag or stable publish occurred during implementation.**
- [ ] **Step 6: Request an independent whole-branch review before integration.**

## Self-Review Checklist

- [x] Spec coverage mapped: stable image signing/promotion (Task 5), four Live ISOs (Tasks 5/8), offline payload/catalog/trust/selection (Tasks 1–4), six-artifact publication/metadata (Task 6), site/docs (Task 7), all acceptance tests (Tasks 1–9).
- [x] High-risk input classes are in Review Focus and have owning test steps in Tasks 2–4 and 6.
- [x] Implementation interfaces are deferred only where Task 1 must establish a working offline Anaconda transport; it explicitly gates Tasks 2–4 and forbids weakening spec requirements.
- [x] The website and OS changes use separate worktrees/repos and separate commits.
- [x] No task publishes an actual stable release or pushes to `main`.
