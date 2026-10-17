# CI Build Reuse Design

**Status:** design for review  
**Date:** 2026-10-17

## Goal

Reduce image-build time and runner work in AgentUX OS CI by testing the exact local image that each matrix leg already built, instead of rebuilding that variant and architecture in a separate smoke job. Preserve native-architecture builds, the no-publish behavior for pull requests, and the rule that public tags are updated only after all image tests pass.

## Current behavior and evidence

- `.github/workflows/build.yml` builds three variants on two native architectures in the `image` matrix.
- A separate `smoke` matrix depends on `image`, but resolves the base and runs `podman build` again for all six variant/architecture pairs. Its comment explicitly chooses rebuild over transferring multi-GB image artifacts.
- The `publish` job waits for both `image` and `smoke`; the `build` aggregate check reports the final workflow result.
- `.github/workflows/boot.yml` separately builds Plasma on pull requests when its path filter matches. It is a KVM/QEMU test, not the container smoke test. Scheduled boot tests already pull the nightly image; release boot tests receive the candidate image digest.
- In PR #58's successful CI run, image builds took about 3.5–5.6 minutes and smoke rebuilds about 4.2–6.5 minutes. The amd64 boot job spent about 9 minutes 52 seconds building Plasma before creating and booting its qcow2.
- The last successful run tested COSMIC Atomic and both other variants on amd64 and arm64. This design preserves that matrix and does not change the COSMIC base or stable-release policy.

## Approaches considered

1. **Build and smoke-test in the same matrix job (recommended).** Run the existing first-login and profile-contract checks against `agentux:ci` immediately after the one build. Only then push the staging image and emit its digest. This avoids a second build, keeps PR jobs write-free, avoids multi-GB artifacts, and makes the tests exercise exactly the image that is pushed.
2. **Push a candidate image, then pull it in smoke.** This avoids rebuilding on same-repository runs but requires publishing images from pull-request workflows or special handling for forks. It also adds registry round trips and broadens the trust/write surface for untrusted PR code. Not recommended.
3. **Transfer OCI archives between jobs.** This keeps jobs isolated but uploads and downloads several gigabytes, adding compression, storage, transfer time, and failure modes. The repository's existing workflow comment already identifies this cost; do not adopt without benchmark evidence.

## Proposed workflow

- Keep one native `image` matrix leg per variant and architecture.
- In each leg, preserve the current base resolution/pull and single `podman build`.
- Move the current `First login and tool checks`, `Installation profile contract`, and their smoke-summary generation from the `smoke` job into the image job, before `Push`.
- Capture the local image ID after build and verify it is unchanged after tests. The tests run the same local `agentux:ci` reference; they must not build or retag another image.
- The image job's token has `packages: write` for staging pushes. Pass it into the smoke container only for `refs/heads/main` (push, schedule, or dispatch); pull requests and non-main dispatches run smoke checks without that token so untrusted image code cannot access publication credentials.
- On pull requests, run all tests but do not push or upload image artifacts. On main/nightly and test dispatches, push the already-tested image to the current staging tag and upload the same per-architecture digest artifact as today.
- Remove the duplicate `smoke` job and make `publish` depend on successful `image` jobs only. Keep signing, manifest-list assembly, signature-policy verification, public-tag promotion, and the named `build` aggregate check intact.
- Leave `boot.yml` unchanged in this first change. Its PR path filter and rootful bootc-image-builder/QEMU path are materially different from container smoke; its multi-GB artifact-versus-rebuild tradeoff needs a separate measured design. Scheduled and release boot tests continue to consume published/candidate images.
- Leave disk cleanup commands unchanged in this change. Record their duration in CI summaries before deciding whether to alter them.

## Failure behavior and security

- Any smoke or profile-contract failure fails the image matrix leg before a staging push; therefore `publish` cannot update public tags.
- Pull-request runs do not push images or upload digest artifacts; the package-write token is not forwarded to smoke-container code on PRs or non-main refs.
- The package-write token is not passed into the image container on pull requests or non-main refs.
- The per-architecture image and existing COSMIC digest resolution remain unchanged.
- No image is rebuilt between test and push, and the test output records the local image ID used.

## Success criteria

1. `build.yml` runs only one container image build per variant/architecture in its image workflow; there is no separate smoke rebuild matrix.
2. First-login, CLI, profile-contract, and COSMIC checks pass against the locally built image on both architectures.
3. Pull requests still publish no images; main/nightly publishes only after all per-architecture checks pass.
4. Signing, signature policy, manifest assembly, release promotion, the branch-protection `build` check, and `boot.yml` behavior remain unchanged.
5. CI run timings confirm the six smoke rebuilds are gone; report remaining image-build and boot-test times separately.

## Out of scope

- Cross-variant layer caching between Plasma, Hyprland, and COSMIC.
- Moving the QEMU/KVM boot test into the image matrix or transferring a multi-GB image to the boot workflow.
- Changing how much runner disk space is reclaimed.
- Changing image contents, base images, signing, or release channels.
