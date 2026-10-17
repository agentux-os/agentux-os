import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const workflow = await readFile(resolve(root, '.github/workflows/build.yml'), 'utf8');
const imageJob = workflow.slice(workflow.indexOf('  image:'), workflow.indexOf('  publish:'));
const publishJob = workflow.slice(workflow.indexOf('  publish:'), workflow.indexOf('  build:'));

assert.match(imageJob, /variant: \[plasma, hyprland, cosmic\]/, 'image matrix covers all desktop variants');
assert.match(imageJob, /needs: contracts/, 'image builds wait for desktop bundle and pin contracts');
assert.match(imageJob, /arch: \[amd64, arm64\]/, 'image matrix covers both native architectures');
assert.match(imageJob, /runner: ubuntu-24\.04-arm/, 'arm64 continues to use its native runner');
assert.match(imageJob, /timeout-minutes: 90/, 'combined build and smoke job remains bounded');

const orderedSteps = [
  'name: Build',
  'name: Capture built image identity',
  'name: First login and tool checks',
  'name: Installation profile contract',
  'name: Verify tested image identity',
  'name: Summary',
  'name: Push',
].map((step) => imageJob.indexOf(step));
assert.ok(orderedSteps.every((position) => position >= 0), 'build, smoke, identity, summary, and push steps all exist in image job');
assert.ok(orderedSteps.every((position, index) => index === 0 || orderedSteps[index - 1] < position), 'image is built, tested, summarized, then pushed in order');

assert.match(imageJob, /image-id-before-tests/, 'built image identity is persisted before smoke checks');
assert.match(imageJob, /podman image inspect --format '\{\{\.Id\}\}' agentux:ci/, 'image identity is inspected from the local CI tag');
assert.match(imageJob, /test "\$before" = "\$after"/, 'smoke checks cannot silently change the image under test');
assert.match(imageJob, /SMOKE_VARIANT=\$\{\{ matrix\.variant \}\}/, 'smoke check receives the matrix variant');
assert.match(imageJob, /tests\/profile\.sh/, 'installation profile contract runs in the image job');
assert.match(imageJob, /GITHUB_TOKEN: \$\{\{ github\.ref == 'refs\/heads\/main' && secrets\.GITHUB_TOKEN \|\| '' \}\}/, 'write-scoped token is only passed to trusted main-branch smoke code');

const pushStep = imageJob.slice(imageJob.indexOf('      - name: Push'), imageJob.indexOf('      - uses: actions/upload-artifact'));
assert.match(pushStep, /if: env\.PUBLISH == 'true'/, 'image push remains disabled for pull requests');
const digestArtifactStep = imageJob.slice(imageJob.indexOf('      - uses: actions/upload-artifact'));
assert.match(digestArtifactStep, /if: env\.PUBLISH == 'true'/, 'digest artifact upload remains disabled for pull requests');

assert.match(publishJob, /needs: \[image\]/, 'publication waits for the tested image matrix only');
assert.doesNotMatch(workflow, /^  smoke:/m, 'duplicate smoke rebuild matrix is removed');

const diskCleanup = imageJob.slice(imageJob.indexOf('      - name: Free disk space'), imageJob.indexOf('      - name: Resolve COSMIC Atomic base'));
assert.match(diskCleanup, /SECONDS/, 'disk cleanup duration is measured');
assert.match(diskCleanup, /GITHUB_STEP_SUMMARY/, 'disk cleanup duration is recorded in the job summary');
