import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const workflow = await readFile(resolve(root, '.github/workflows/release.yml'), 'utf8');
const publisher = await readFile(resolve(root, '.github/scripts/publish-iso.sh'), 'utf8');
const readme = await readFile(resolve(root, 'README.md'), 'utf8');

for (const [job, variant, image] of [
  ['iso-plasma', 'plasma', 'agentux@${{ needs.candidate.outputs.plasma }}'],
  ['live-plasma', 'plasma', 'agentux@${{ needs.candidate.outputs.plasma }}'],
  ['iso-cosmic', 'cosmic', 'agentux-cosmic@${{ needs.candidate.outputs.cosmic }}'],
  ['live-cosmic', 'cosmic', 'agentux-cosmic@${{ needs.candidate.outputs.cosmic }}'],
]) {
  const start = workflow.indexOf(`  ${job}:`);
  assert.ok(start >= 0, `release defines ${job}`);
  const nextJob = [...workflow.matchAll(/^  [\w-]+:\s*$/gm)]
    .find((match) => match.index > start);
  const next = nextJob?.index ?? -1;
  const block = workflow.slice(start, next < 0 ? workflow.length : next);
  assert.match(block, new RegExp(`variant: ${variant}\\n`), `${job} selects ${variant}`);
  assert.ok(block.includes(image), `${job} uses the ${variant} candidate digest`);
}

assert.match(workflow, /needs: \[candidate, boot, iso-plasma, iso-cosmic, live-plasma, live-cosmic\]/,
  'publication waits for all tested Plasma and COSMIC ISO jobs');
assert.doesNotMatch(workflow, /hyprland/i, 'the retired Hyprland variant is not released');
// agentux-<desktop>-<live|installer>-<tag>-<arch>, for every desktop and arch.
const isoNames = (version) => ['plasma', 'cosmic'].flatMap((desktop) => ['live', 'installer'].flatMap((kind) =>
  ['x86_64', 'aarch64'].map((arch) => `agentux-${desktop}-${kind}-${version}-${arch}`)));
const expectedNames = isoNames('${{ github.ref_name }}');
const expectStart = workflow.indexOf('          EXPECT:');
const expectEnd = workflow.indexOf('        run:', expectStart);
const expectBlock = workflow.slice(expectStart, expectEnd);
for (const name of expectedNames) {
  assert.ok(expectBlock.includes(name), `release publication requires ${name}`);
}
assert.equal((expectBlock.match(/agentux-[a-z]+-(live|installer)-/g) || []).length, 8, 'a release publishes exactly eight ISOs');

for (const name of isoNames('$tag')) {
  assert.ok(publisher.includes(name), `release notes link the ${name} ISO`);
}
assert.match(publisher, /iso\/stable\/ holds the newest release only/, 'the stable channel drops ISOs a release no longer ships');
assert.match(publisher, /--title "AgentUX \$tag"/, 'release title uses the generated version, not a stale hard-coded version');
assert.match(publisher, /gh release edit "\$tag"[\s\S]*?--notes-file "\$notes"/,
  'rerunning publication corrects an existing release title and description');
assert.match(publisher, /The x86_64 ISOs were booted and their installed systems checked in a VM/,
  'release notes describe VM validation for the expanded ISO set');
