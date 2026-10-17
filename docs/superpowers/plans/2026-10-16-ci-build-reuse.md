# CI Build Reuse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the six duplicate smoke image builds by running smoke and profile-contract tests against each image matrix leg's exact local build before any push.

**Architecture:** Keep the existing native variant/architecture matrix and move its smoke checks into each `image` job after `Build`. Verify the local image ID remains unchanged through testing, then retain the current conditional push and digest artifact flow; remove the separate `smoke` job and make publication depend on `image` alone.

**Tech Stack:** GitHub Actions YAML, Podman, Bash, Node.js contract test, actionlint.

**Spec:** `docs/superpowers/specs/2026-10-17-ci-build-reuse-design.md`

## Global Constraints

- Preserve the three variants (`plasma`, `hyprland`, `cosmic`) and native `amd64`/`arm64` builds.
- Bound the combined image-build-and-smoke job to 90 minutes.
- Test the same local `agentux:ci` image that was built; do not rebuild or retag between build, tests, and push.
- Pull requests run image tests but do not push to GHCR or upload digest artifacts; do not pass the job's package-write token into the smoke container on PR or non-main refs.
- Non-PR pushes happen only after smoke and profile-contract tests pass; preserve current staging tags and digest artifact names.
- Keep signing, manifest assembly, signature-policy verification, public-tag promotion, and the required `build` check intact.
- Do not change `.github/workflows/boot.yml`, image contents, base resolution, or disk cleanup commands.

## Review Focus

- A smoke/profile failure must stop before the image push; assert test steps precede `Push` and publication still needs successful `image`.
- Tests must not silently inspect a different image reference; assert the image ID before and after tests is identical.
- PR behavior must not publish; retain `if: env.PUBLISH == 'true'` on both push and digest upload and keep the package-write token out of the smoke container.
- Each variant/architecture must keep the existing smoke inputs and native runner mapping; inspect the relocated steps and matrix after editing.
- Existing publication and required-check semantics must survive removal of `smoke`; run actionlint and inspect `needs`/aggregate conditions.

---

### Task 1: Reuse each image-matrix build for smoke checks

**Files:**
- Create: `tests/build-workflow-contract.mjs`
- Modify: `.github/workflows/build.yml`

**Interfaces:**
- Consumes: `.github/workflows/build.yml` and the existing smoke/profile scripts.
- Produces: the existing `image` matrix as the sole builder and smoke-test gate before `publish`.

- [ ] **Step 1: Write the failing workflow contract test**

Create `tests/build-workflow-contract.mjs` using the repository's existing Node assertion style. Check variant/architecture matrix entries and 90-minute job bound; step order `Build`, ID capture, first-login check, profile check, ID verification, summary, and `Push`; unchanged conditional push and digest upload; `publish.needs: [image]`; timed disk-cleanup summary; and absence of a `smoke:` job.

- [ ] **Step 2: Run the contract test and confirm it fails against the current workflow**

Run: `node tests/build-workflow-contract.mjs`
Expected: FAIL because smoke checks still live in the separate rebuild matrix and `publish` still depends on `smoke`.

- [ ] **Step 3: Record the existing local image ID after Build**

Add a step after `Build` that writes `podman image inspect --format '{{.Id}}' agentux:ci` to `$RUNNER_TEMP/image-id-before-tests` and logs the ID to `$GITHUB_STEP_SUMMARY`.

- [ ] **Step 4: Move smoke checks and summary into the image matrix job**

Relocate the existing `First login and tool checks`, `Installation profile contract`, and always-run `Summary` steps from `smoke` to `image`, after ID capture and before `Push`. Preserve their commands, mounts, remaining environment, and variant/architecture labels; pass `GITHUB_TOKEN` only when `github.ref == 'refs/heads/main'` because this job has `packages: write`. Use the image job's existing COSMIC base resolution. After profile tests, compare the inspected ID with `$RUNNER_TEMP/image-id-before-tests` and fail if they differ; then retain the always-run summary step. Wrap the existing disk cleanup with Bash `SECONDS` timing and append its duration to `$GITHUB_STEP_SUMMARY`, without changing the cleanup commands.

- [ ] **Step 5: Remove the duplicate smoke matrix and update publication dependency**

Delete the `smoke` job, including its second base pull and `podman build`. Invoke `node tests/build-workflow-contract.mjs` from the existing `lint` job. Change `publish.needs` from `[image, smoke]` to `[image]`. Keep `build.needs: [image, publish]`, its `always()` condition, and its success/skipped result checks unchanged.

- [ ] **Step 6: Run focused and workflow validation**

Run: `node tests/build-workflow-contract.mjs`
Expected: PASS for all matrix, ordering, image-identity, conditional-publish, and no-smoke-job assertions.

Run: `actionlint .github/workflows/build.yml .github/workflows/boot.yml`
Expected: no diagnostics.

Run: `node tests/cosmic-contract.mjs`
Expected: PASS; COSMIC variant contract remains intact.

- [ ] **Step 7: Review, validate whitespace, and commit**

Run: `git diff --check`
Expected: no whitespace errors.

Confirm `boot.yml` is unchanged, all smoke tests run before `Push`, pull requests still skip both push and image digest upload, and `publish` is gated only by successful image jobs. Then commit:

```bash
git add .github/workflows/build.yml tests/build-workflow-contract.mjs
git add docs/superpowers/specs/2026-10-17-ci-build-reuse-design.md docs/superpowers/plans/2026-10-16-ci-build-reuse.md
git commit -m "ci: reuse built images for smoke checks"
```

## Self-review

- Spec coverage: same native matrix, one build per pair, first-login/profile checks before push, unchanged PR write behavior, digest flow, publication gate, required aggregate check, signing/promotion, and unchanged boot workflow are covered.
- Scope: one CI workflow subsystem; the static contract test and workflow are one coherent deliverable.
- Validation: Node contract test, existing COSMIC contract test, actionlint, and whitespace check cover the changed workflow and its existing variant assumptions.
- Out of scope remains out of scope: KVM image sharing, cross-variant caching, and disk-cleanup changes.
