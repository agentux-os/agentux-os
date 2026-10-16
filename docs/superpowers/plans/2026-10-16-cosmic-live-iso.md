# COSMIC Live ISO Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan. Work in the OS and Desktop worktrees named below; do not merge or push without the user's explicit integration direction.

**Goal:** Add a second, COSMIC-based AgentUX Live ISO while preserving the current Plasma and Hyprland live experiences and leaving the offline installer ISO unchanged.

**Architecture:** Add a distinct signed bootc image repository (`agentux-cosmic`) and COSMIC desktop overlay in `agentux-desktop`. Move only desktop-independent setup/autostart assets into a shared desktop layer if inspection confirms they are currently Plasma-bound. Extend the Live ISO build/install/publish path so each live ISO installs and tracks its matching image. Keep COSMIC nightly until image, architecture, install, rollback, and session checks pass.

**Tech Stack:** Fedora bootc/OCI images, Podman, GitHub Actions, shell validation, Anaconda live installer, COSMIC Atomic session, existing AgentUX Core/Cockpit, QEMU/KVM.

**Spec:** [`docs/superpowers/specs/2026-10-16-cosmic-live-iso-design.md`](../specs/2026-10-16-cosmic-live-iso-design.md)

**Worktrees:** OS: `C:\Users\wende\Projects\agentux-os\.worktrees\cosmic-live-iso` (`agent/cosmic-live-iso`); Desktop: `C:\Users\wende\Projects\agentux-os\.worktrees\cosmic-live-desktop` (`agent/cosmic-live-desktop`). Keep commits repository-local and coordinate shared contracts through this plan.

## Global Constraints

- Do not change the existing offline installer workflow or add COSMIC packages to its payload.
- Do not combine Plasma and COSMIC in one installed image. Keep existing Plasma and Hyprland behavior intact.
- COSMIC Live must install and track only `ghcr.io/agentux-os/agentux-cosmic`; reject mismatched image references at build time.
- COSMIC must not include Plasma session packages, Plasma AgentUX overlay, or Plasma-specific live desktop layout/note mechanisms.
- Preserve shared Core, Cockpit, profile application, fake-agent demo, no-login-download behavior, and no persistent-disk writes before install.
- Resolve the upstream COSMIC Atomic nightly tag to immutable per-architecture digests for each build/smoke job; validate its bootc/session requirements and record the selected digest. Upstream Quay blobs expire after four weeks, so avoid long-lived digest pins. Keep COSMIC nightly-only and do not claim upstream source-signature verification unless it is separately established.
- Keep COSMIC nightly-only until launch criteria in the spec are satisfied. Do not claim a performance win without repeatable same-machine measurements.
- Keep changes scoped to the two named worktrees. Do not discard or rewrite unrelated user changes.

## Review Focus / High-Risk Conditions

1. **Upstream image/tag or architecture unavailable / not bootc-compatible.** First image task must verify the exact source image and architecture manifests; test the documented fallback decision without silently substituting an unverified tag.
2. **COSMIC session, first-run, or XDG autostart fails for live user or installed user.** Add COSMIC overlay checks and VM smoke assertions for session identity, Welcome/Cockpit launch, and the shared setup service/profile path.
3. **Live installer installs or tracks Plasma due to image-ID/reference mismatch.** Add shell tests for `agentux-cosmic` accepted references and Plasma/Hyprland/wrong-registry references rejected, then verify installed deployment reference in VM test.
4. **Signing, signature policy, or release promotion omits the new repository.** Extend signed and unsigned policy fixtures and require COSMIC digest/signature checks before any COSMIC public tag is promoted.
5. **Live boot downloads, writes persistent storage, or presents misleading performance evidence.** Assert disabled first-login/download services and fake-agent mode; inspect live VM disk state before install. Benchmark both desktops with identical VM settings and record renderer/configuration.

## File Map

**OS repository (`agentux-os`):** `Containerfile`; `.github/workflows/build.yml`, `release.yml`, `live.yml`; `live/Containerfile`, `live/build.sh`, `live/install.ks`, `live/livesys-session-extra`, live note/layout assets; `tests/sigpolicy.sh`, `tests/live.sh`, `tests/live-vm.sh`, `tests/boot.sh`; `README.md` and download/release documentation.

**Desktop repository (`agentux-desktop`):** existing `plasma/` overlay and checks; add a shared desktop-independent overlay (name/location decided after inspecting current tree) and `cosmic/` overlay with session defaults, branding, supported autostart/setup integration, and independent checks; update `.github/workflows/ci.yml`, release packaging, and `README.md`.

Do not edit `.github/workflows/iso.yml` except if a test proves the existing offline ISO is coupled to a shared mapping that must be made explicit; in that case preserve its output and add a regression assertion.

## Implementation Tasks

### Task 1: Establish shared desktop contract and COSMIC overlay in Desktop repo

**Files:** Desktop `plasma/` (existing assets only where extraction is necessary), new shared overlay, new `cosmic/`, `README.md`, `.github/workflows/ci.yml`, Desktop release workflow.

1. **Inspect and record the desktop asset boundary.** Identify setup catalog/backend, Cockpit/Welcome launchers, XDG autostart, Plasma-only defaults, and RPM/archive packaging. Keep the current Plasma archive contents and behavior backward-compatible.
2. **Write failing overlay checks first.** Add checks that shared assets exist exactly once in the shared layer, COSMIC session/branding assets exist, COSMIC overlay contains no Plasma session dependency, and Plasma's current check still passes. Run the checks and confirm the new COSMIC assertions fail before adding assets.
3. **Implement the minimal shared/COSMIC assets.** Ensure COSMIC can start the existing AgentUX Welcome/Cockpit experience and setup catalog via supported XDG/systemd integration, with no Plasma panel, widget, or setup dependency. Use upstream-supported COSMIC configuration locations and avoid inventing unsupported keys.
4. **Package deterministic artifacts.** Update Desktop release packaging to publish versioned shared and COSMIC overlay artifacts alongside the existing Plasma artifact; document artifact names and compatibility/version pairing. Preserve existing Plasma artifact name/content contract.
5. **Verify Desktop repo.** Run the Plasma checker, new shared/COSMIC checkers, Cockpit npm tests and typecheck. CI should exercise all overlays and package artifact contents. Commit this task in Desktop repo.

### Task 2: Add and validate the COSMIC bootc image variant

**Files:** OS `Containerfile`, variant package/build helpers if present, `tests/boot.sh`, `tests/smoke.sh`, OS README build section.

1. **Add a source-image preflight.** Resolve Fedora COSMIC Atomic tag `44` to the unique Linux `amd64` or `arm64` OCI digest in each CI job, pull/build by that immutable digest, and record it in the GitHub Actions summary. Validate the base contains the COSMIC session and supported initial-setup backend. The upstream Quay retention annotation is four weeks; no long-lived digest pin or guessed duplicate package manifest is used.
2. **Add failing variant contract tests.** Test accepted variants (`plasma`, `hyprland`, `cosmic`), reject unknown values, and assert Cosmic image metadata, required COSMIC session, shared AgentUX services/profile service, and absence of Plasma session/overlay packages. Keep existing variants' assertions unchanged.
3. **Build the `cosmic` variant.** Add the `agentux-cosmic` repository mapping and install the Desktop shared + COSMIC artifacts. Do not install the Plasma artifact. Preserve image signature policy and Core/Cockpit/profile behavior.
4. **Validate native builds.** Build COSMIC natively on `amd64` and `arm64`, inspect installed package manifests and image labels, then run applicable static smoke tests (`tests/smoke.sh`, `tests/boot.sh`). Record exact commands and any ARM boot-test limitation.
5. **Commit OS image task.** Commit only after tests establish both positive COSMIC and negative Plasma-exclusion checks.

### Task 3: Extend image build, signature, and promotion workflows

**Files:** OS `.github/workflows/build.yml`, `.github/workflows/release.yml`, `tests/sigpolicy.sh`, image signature-policy configuration in `Containerfile` or its source files.

1. **Add failing workflow/policy checks.** Extend policy tests to require all three repositories and verify a valid signed COSMIC image succeeds while unsigned/wrong-identity images fail. Add a static workflow contract check if needed to catch variant/image mapping drift.
2. **Extend build matrix and mappings.** Add `cosmic` to native `amd64`/`arm64` build jobs, digest artifacts, image repository mapping, signing, and per-architecture policy checks. Ensure pull requests build/test without publishing public tags.
3. **Extend promotion deliberately.** Add COSMIC to digest promotion and stable release only behind the launch gate. Until the gate is satisfied, publish nightly/test channels only and ensure release workflow cannot accidentally create `:stable` for COSMIC.
4. **Exercise CI policy.** Run shell/static tests locally; workflow CI must build both architectures and verify signatures/policy before publishing any COSMIC nightly tag. Confirm Plasma and Hyprland release mappings remain unchanged.
5. **Commit workflow task.** Include tests and a concise operator note describing the COSMIC nightly gate.

### Task 4: Build COSMIC Live ISO and match its install/update target

**Files:** OS `live/Containerfile`, `live/build.sh`, `live/install.ks`, live systemd/autostart/note assets, `.github/workflows/live.yml`, `tests/live.sh`, `tests/live-vm.sh`.

1. **Add failing live-build contract tests.** Cover image IDs, artifact labels, session selection, installer target, tracking target, and rejection of mismatched or malformed references. Assert COSMIC path does not require Plasma note/widget/layout packages and the Plasma path remains unchanged.
2. **Add COSMIC live presentation.** Build a separate COSMIC Live ISO with COSMIC as default session, AgentUX branding and a COSMIC-compatible explanation/demo affordance. Keep the shared Cockpit and fake-agent demo. No network downloads at login; network is required only when the user invokes installation.
3. **Wire signed install and tracking references.** Set `INSTALL_IMAGE` and `TRACK_IMAGE` to `ghcr.io/agentux-os/agentux-cosmic` tags/digests. Validate both references before image construction, render `install.ks`, and verify no placeholders remain. Ensure installed deployment and update channel remain COSMIC.
4. **Extend live workflow.** Produce separate explicit artifacts such as `agentux-cosmic-live-<version>-<arch>.iso` for x86_64 and aarch64. Add per-arch build and available boot tests without changing the existing offline installer matrix or artifacts.
5. **VM validation.** Boot COSMIC live ISO; assert COSMIC session, Cockpit, demo, fake mode, disabled first-login installers, and no persistent-disk writes before install. Install online on x86_64, reboot, verify COSMIC image/channel, Core/profile services, then verify rollback. Run existing Plasma and Hyprland live tests as regression checks.
6. **Commit Live ISO task.** Include test output or CI link in commit description; do not promote COSMIC stable here.

### Task 5: Document choices, launch gate, and evidence-based comparison

**Files:** OS `README.md`, download/release documentation and index scripts, Desktop `README.md`, benchmark procedure/results document, screenshot assets if maintained in repo.

1. **Add regression checks for published choices.** Check that docs list Plasma and COSMIC Live choices distinctly, label architectures and network installation, and do not describe COSMIC as an offline installer or default. Verify download-index artifact naming matches workflow outputs.
2. **Update user/operator docs.** Explain the two live options, COSMIC's nightly/experimental status until launch criteria pass, network requirement for installation, supported architectures, and unchanged offline installer.
3. **Capture and review both desktops.** Use the same VM display configuration; inspect screenshots for startup, AgentUX branding, Cockpit/demo, and obvious clipping or missing UI. Keep screenshots as evidence only if repo policy permits.
4. **Measure fairly.** Record idle RAM, CPU, login-to-interactive time, and simple interaction latency for Plasma and COSMIC on the same host/VM settings; include renderer, vCPU/RAM/video settings, repeated-run method, and variance. Label VirtualBox results as VirtualBox-only. Make no comparative claim without repeatability.
5. **Commit docs/evidence task.** Keep performance conclusion appropriately qualified and COSMIC stable gate explicitly unchecked unless all launch criteria have evidence.

### Task 6: End-to-end release readiness review

1. Run the Desktop overlay/package CI and OS image, signature, live, and documentation checks together against the paired commits/artifact versions.
2. Confirm existing Plasma and Hyprland build/live checks and offline installer ISO workflow are unchanged and green.
3. Review architecture coverage, signing identity, rollback, installation target, screenshots, and performance evidence against every item in the approved spec.
4. If any launch criterion is unsupported (especially ARM boot/install, signature verification, or rollback), keep COSMIC nightly-only and document the precise gap; do not weaken the gate.
5. Commit the final readiness record in the OS repo. PR creation, merge, stable promotion, and remote changes require a separate explicit instruction.

## Verification Commands

Run the repository-native checks found during implementation; the following are expected entry points, with exact script names to be confirmed against each repo's README/CI:

- Desktop: `bash plasma/check.sh`, new shared and COSMIC overlay check scripts, `npm test`, and `npm run typecheck` from the Cockpit project; inspect release archive contents.
- OS: `bash tests/smoke.sh`, `bash tests/boot.sh`, `bash tests/sigpolicy.sh`, `bash tests/live.sh`, and `bash tests/live-vm.sh` in the required Podman/QEMU/KVM environment.
- CI: native image builds for `amd64`/`arm64`, signature verification against the image's shipped policy, COSMIC ISO boot/install/rollback workflow, plus existing Plasma/Hyprland and offline ISO jobs.
- Documentation/artifacts: validate generated download index and assert exact artifact names for each desktop and architecture.

## Self-Review Checklist

- [x] Spec scope preserved: two Live ISOs; offline installer unchanged; separate COSMIC image; nightly gate; x86_64/aarch64; no language/Core scope creep.
- [x] Task order follows dependencies: Desktop assets → bootc image → image signing/release → Live ISO/install → docs/evidence → readiness.
- [x] High-risk conditions each map to named checks/tests in implementation tasks.
- [x] Tasks are separable and commit-sized; cross-repo artifacts have a named pairing contract.
- [x] Does not claim COSMIC is lighter; requires repeatable measurement.
- [x] Explicitly protects existing worktrees and avoids merge/push authorization assumptions.
- [x] Command names are described as expected entry points and must be confirmed against actual repo scripts before execution.
