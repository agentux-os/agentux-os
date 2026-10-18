import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const workflow = await readFile(resolve(root, '.github/workflows/offline-media-prototype.yml'), 'utf8');
const triggers = workflow.slice(workflow.indexOf('\non:'), workflow.indexOf('\npermissions:'));
const jobs = workflow.slice(workflow.indexOf('\njobs:'));
const contractJob = jobs.slice(jobs.indexOf('\n  contracts:'), jobs.indexOf('\n  payload-install:'));
const payloadJob = jobs.slice(jobs.indexOf('\n  payload-install:'));

assert.match(triggers, /^  pull_request:\r?\n    branches: \[main\]/m, 'PR updates targeting main trigger the fast contract workflow');
assert.match(triggers, /^  workflow_dispatch:\s*$/m, 'the full offline install proof remains manually runnable');
assert.match(contractJob, /node tests\/offline-media-prototype\.mjs/, 'fast catalog contracts run on PRs');
assert.match(contractJob, /node tests\/offline-media-workflow-contract\.mjs/, 'workflow scheduling contract runs on PRs');
assert.match(payloadJob, /needs: contracts/, 'full proof waits for the contract checks');
assert.match(payloadJob, /if: github\.event_name == 'workflow_dispatch'/, 'expensive multiarch payload/install jobs only run on manual dispatch');
assert.match(payloadJob, /skopeo copy/, 'manual validation still exports the real OCI payloads');
assert.match(payloadJob, /bootc install to-disk/, 'manual validation still tests offline disk installation');

console.log('Offline media workflow trigger contracts passed.');
