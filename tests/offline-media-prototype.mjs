import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { buildCatalog, verifyCatalog } from '../installer/offline-prototype/catalog.mjs';

const digest = (letter) => `sha256:${letter.repeat(64)}`;
const variants = ['plasma', 'hyprland', 'cosmic'];
const imageRepositories = {
  plasma: 'ghcr.io/agentux-os/agentux',
  hyprland: 'ghcr.io/agentux-os/agentux-hyprland',
  cosmic: 'ghcr.io/agentux-os/agentux-cosmic',
};
const root = await mkdtemp(join(tmpdir(), 'agentux-offline-prototype-'));

try {
  const payloadDir = join(root, 'payloads');
  await mkdir(payloadDir);
  const images = [];
  for (const [index, variant] of variants.entries()) {
    const filename = `${variant}.oci.tar.zst`;
    await writeFile(join(payloadDir, filename), `signed fixture payload for ${variant}`);
    images.push({ variant, image: `${imageRepositories[variant]}@${digest(String(index + 1))}`, filename });
  }

  const catalog = await buildCatalog({ payloadDir, arch: 'aarch64', version: 'v0.5.7', images });
  assert.deepEqual(catalog.variants, variants, 'catalog has all variants in deterministic order');
  assert.equal(catalog.arch, 'aarch64');
  assert.equal(catalog.payloads[0].imageDigest, digest('1'));
  assert.ok(catalog.payloads.every(({ size, sha256 }) => size > 0 && /^[a-f0-9]{64}$/.test(sha256)));
  assert.deepEqual(await verifyCatalog({ catalog, payloadDir, expectedArch: 'aarch64' }), { valid: true, variants });

  await assert.rejects(
    () => buildCatalog({ payloadDir, arch: 'x86_64', version: 'v0.5.7', images: images.slice(0, 2) }),
    /exactly plasma, hyprland, cosmic/,
    'incomplete variant sets are rejected',
  );
  await assert.rejects(
    () => buildCatalog({ payloadDir, arch: 'x86_64', version: 'v0.5.7', images: variants.map((variant) => ({ variant, image: `${imageRepositories[variant]}:latest`, filename: `${variant}.oci.tar.zst` })) }),
    /immutable sha256 digest/,
    'mutable registry tags cannot enter the catalog',
  );
  await assert.rejects(
    () => verifyCatalog({ catalog, payloadDir, expectedArch: 'x86_64' }),
    /architecture mismatch/,
    'cross-architecture payload catalogs are rejected',
  );

  await writeFile(join(payloadDir, '../outside.oci.tar.zst'), 'must not escape payload directory');
  const escaped = structuredClone(catalog);
  escaped.payloads[0].filename = '../outside.oci.tar.zst';
  await assert.rejects(
    () => verifyCatalog({ catalog: escaped, payloadDir, expectedArch: 'aarch64' }),
    /unsafe payload filename/,
    'catalog filenames cannot escape the media payload directory',
  );

  await writeFile(join(payloadDir, 'cosmic.oci.tar.zst'), 'altered after signing');
  await assert.rejects(
    () => verifyCatalog({ catalog, payloadDir, expectedArch: 'aarch64' }),
    /payload integrity mismatch: cosmic/,
    'post-catalog payload alteration is detected',
  );

  const saved = await readFile(join(payloadDir, 'plasma.oci.tar.zst'));
  assert.ok(saved.length > 0, 'catalog verification did not remove or rewrite payloads');
} finally {
  await rm(root, { recursive: true, force: true });
}

console.log('offline media prototype catalog contracts passed');
