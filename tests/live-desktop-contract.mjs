import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const liveTest = resolve(root, 'tests/live.sh');

function sessionProcesses(imageId) {
  return execFileSync('bash', [liveTest], {
    encoding: 'utf8',
    env: { ...process.env, LIVE_PHASE: 'desktop-processes', LIVE_TEST_VARIANT: imageId },
  }).trim().split('\n');
}

assert.deepEqual(sessionProcesses('agentux'), ['kwin_wayland', 'plasmashell']);
assert.deepEqual(sessionProcesses('agentux-hyprland'), ['Hyprland', 'lxqt-policykit-agent']);
assert.deepEqual(sessionProcesses('agentux-cosmic'), ['cosmic-session', 'cosmic-comp']);
console.log('Live desktop variant process contracts passed.');
