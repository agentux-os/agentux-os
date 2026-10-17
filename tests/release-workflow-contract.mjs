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
  ['iso-hyprland', 'hyprland', 'agentux-hyprland@${{ needs.candidate.outputs.hyprland }}'],
  ['live-plasma', 'plasma', 'agentux@${{ needs.candidate.outputs.plasma }}'],
  ['live-hyprland', 'hyprland', 'agentux-hyprland@${{ needs.candidate.outputs.hyprland }}'],
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

assert.match(workflow, /needs: \[candidate, boot, iso-plasma, iso-hyprland, live-plasma, live-hyprland\]/,
  'publication waits for all tested Plasma and Hyprland ISO jobs');
assert.match(workflow, /variant: hyprland[\s\S]*?image: ghcr\.io\/\$\{\{ github\.repository_owner \}\}\/agentux-hyprland@\$\{\{ needs\.candidate\.outputs\.hyprland \}\}/,
  'Hyprland ISOs use the tagged Hyprland image digest');
const expectedNames = [
  'agentux-${{ github.ref_name }}-x86_64',
  'agentux-${{ github.ref_name }}-aarch64',
  'agentux-live-${{ github.ref_name }}-x86_64',
  'agentux-live-${{ github.ref_name }}-aarch64',
  'agentux-hyprland-${{ github.ref_name }}-x86_64',
  'agentux-hyprland-${{ github.ref_name }}-aarch64',
  'agentux-hyprland-live-${{ github.ref_name }}-x86_64',
  'agentux-hyprland-live-${{ github.ref_name }}-aarch64',
];
const expectStart = workflow.indexOf('          EXPECT:');
const expectEnd = workflow.indexOf('        run:', expectStart);
const expectBlock = workflow.slice(expectStart, expectEnd);
for (const name of expectedNames) {
  assert.ok(expectBlock.includes(name), `release publication requires ${name}`);
}
assert.doesNotMatch(workflow, /agentux-cosmic/, 'COSMIC is not promoted by stable releases');

for (const name of [
  'agentux-live-$tag-x86_64', 'agentux-live-$tag-aarch64',
  'agentux-$tag-x86_64', 'agentux-$tag-aarch64',
  'agentux-hyprland-live-$tag-x86_64', 'agentux-hyprland-live-$tag-aarch64',
  'agentux-hyprland-$tag-x86_64', 'agentux-hyprland-$tag-aarch64',
]) {
  assert.ok(publisher.includes(name), `release notes link the ${name} ISO`);
}
assert.match(readme, /agentux-hyprland-live-x86_64\.iso[\s\S]*agentux-hyprland-x86_64\.iso/,
  'download documentation lists the newest Hyprland stable live and installer ISOs');
assert.match(publisher, /--title "AgentUX \$tag"/, 'release title uses the generated version, not a stale hard-coded version');
assert.match(publisher, /gh release edit "\$tag"[\s\S]*?--notes-file "\$notes"/,
  'rerunning publication corrects an existing release title and description');
assert.match(publisher, /The x86_64 ISOs were booted and their installed systems checked in a VM/,
  'release notes describe VM validation for the expanded ISO set');
