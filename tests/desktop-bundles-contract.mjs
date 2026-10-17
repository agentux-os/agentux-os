import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const containerfile = await readFile('Containerfile', 'utf8');
const install = containerfile.slice(containerfile.indexOf('# AgentUX itself'));
const smoke = await readFile('tests/smoke.sh', 'utf8');
const buildWorkflow = await readFile('.github/workflows/build.yml', 'utf8');
// Desktop bundles exist from agentux-desktop 0.5.2 on; any later release pins too.
const desktopPin = containerfile.match(/^ARG AGENTUX_DESKTOP_VERSION=(\d+)\.(\d+)\.(\d+)$/m);
assert.ok(desktopPin, 'image pins a desktop bundle release');
const [major, minor, patch] = desktopPin.slice(1).map(Number);
assert.ok(major > 0 || minor > 5 || (minor === 5 && patch >= 2), `desktop release ${desktopPin.slice(1).join('.')} ships bundles (0.5.2 or later)`);

for (const bundle of ['common', 'plasma', 'cosmic']) {
  const pin = containerfile.match(new RegExp(`^ARG AGENTUX_${bundle.toUpperCase()}_SHA256=([a-f0-9]{64})$`, 'm'));
  assert.ok(pin, `${bundle} SHA-256 is pinned`);
  assert.notEqual(pin[1], '0'.repeat(64), `${bundle} SHA-256 cannot be a placeholder`);
  assert.ok(install.includes('agentux-desktop-' + bundle + '-${AGENTUX_DESKTOP_VERSION}.tar.gz'), `${bundle} uses the versioned archive name`);
}

const commonExtract = install.indexOf('tar -xzf "/tmp/$common"');
const variantSelect = install.indexOf('if [ "$VARIANT" = cosmic ]; then');
assert.ok(commonExtract >= 0 && variantSelect > commonExtract, 'common bundle is extracted before selecting exactly one desktop overlay');
for (const sumFile of ['/tmp/common.sha256', '/tmp/cosmic.sha256', '"/tmp/$plasma.sha256"']) {
  const checkAt = install.indexOf(`sha256sum --check --strict ${sumFile}`);
  const extractAt = install.indexOf('tar -xzf', checkAt);
  assert.ok(checkAt >= 0 && extractAt > checkAt, `${sumFile} is verified before archive extraction`);
}
assert.match(install, /agentux-cockpit-\$\{AGENTUX_DESKTOP_VERSION\}-1\.\$\{arch\}\.rpm/, 'Cockpit RPM stays independent of desktop overlay selection');
assert.match(smoke, /shared setup backend is installed[\s\S]*shared setup catalog is installed/, 'smoke checks common setup files on every image');
assert.match(smoke, /COSMIC image excludes Plasma-owned settings/, 'COSMIC smoke rejects Plasma configuration');
assert.match(buildWorkflow, /node tests\/desktop-bundles-contract\.mjs[\s\S]*tests\/bump-agentux\.sh/, 'build CI runs image bundle and atomic pin contracts');
console.log('image desktop bundle contract: OK');
