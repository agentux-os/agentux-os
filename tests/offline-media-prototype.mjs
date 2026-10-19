import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import * as catalogModule from '../installer/offline-prototype/catalog.mjs';
const { buildCatalog, verifyCatalog } = catalogModule;

const digest = (letter) => `sha256:${letter.repeat(64)}`;
const variants = ['plasma', 'cosmic'];
const imageRepositories = {
  plasma: 'ghcr.io/agentux-os/agentux',
  cosmic: 'ghcr.io/agentux-os/agentux-cosmic',
};
const root = await mkdtemp(join(tmpdir(), 'agentux-offline-prototype-'));

try {
  const payloadDir = join(root, 'payloads');
  await mkdir(payloadDir);
  const images = [];
  for (const [index, variant] of variants.entries()) {
    const filename = `${variant}.oci.tar`;
    await writeFile(join(payloadDir, filename), `signed fixture payload for ${variant}`);
    images.push({ variant, signedIndex: `${imageRepositories[variant]}@${digest(String(index + 4))}`, image: `${imageRepositories[variant]}@${digest(String(index + 1))}`, filename });
  }

  const catalog = await buildCatalog({ payloadDir, arch: 'aarch64', version: 'v0.5.7', images });
  assert.deepEqual(catalog.variants, variants, 'catalog has all variants in deterministic order');
  assert.equal(catalog.arch, 'aarch64');
  assert.equal(catalog.payloads[0].imageDigest, digest('1'));
  assert.equal(catalog.payloads[0].signedIndexDigest, digest('4'), 'catalog records the signed index the payload came from');
  assert.ok(catalog.payloads.every(({ size, sha256 }) => size > 0 && /^[a-f0-9]{64}$/.test(sha256)));
  assert.deepEqual(await verifyCatalog({ catalog, payloadDir, expectedArch: 'aarch64' }), { valid: true, variants });

  assert.equal(typeof catalogModule.parseImageManifest, 'function', 'catalog exports the workflow manifest parser');
  assert.deepEqual(
    catalogModule.parseImageManifest(variants.map((variant, index) => [
      variant,
      `${imageRepositories[variant]}@sha256:${'f'.repeat(64)}`,
      `${imageRepositories[variant]}@sha256:${'abc'[index].repeat(64)}`,
      `${variant}.oci.tar`,
    ].join('\t')).join('\n')),
    [
      { variant: 'plasma', signedIndex: 'ghcr.io/agentux-os/agentux@sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff', image: 'ghcr.io/agentux-os/agentux@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', filename: 'plasma.oci.tar' },
      { variant: 'cosmic', signedIndex: 'ghcr.io/agentux-os/agentux-cosmic@sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff', image: 'ghcr.io/agentux-os/agentux-cosmic@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', filename: 'cosmic.oci.tar' },
    ],
    'four-column workflow manifests map to variant, signed index, exported image, and filename',
  );
  assert.throws(
    () => catalogModule.parseImageManifest(`plasma\t${imageRepositories.plasma}@sha256:${'f'.repeat(64)}\t${imageRepositories.plasma}@sha256:${'a'.repeat(64)}\tplasma.oci.tar\textra`),
    /invalid image manifest row/,
    'unexpected manifest columns are rejected instead of silently mis-mapped',
  );

  await assert.rejects(
    () => buildCatalog({ payloadDir, arch: 'x86_64', version: 'v0.5.7', images: images.slice(0, 1) }),
    /exactly plasma, cosmic/,
    'incomplete variant sets are rejected',
  );
  await assert.rejects(
    () => buildCatalog({ payloadDir, arch: 'x86_64', version: 'v0.5.7', images: variants.map((variant) => ({ variant, signedIndex: `${imageRepositories[variant]}@${digest('f')}`, image: `${imageRepositories[variant]}:latest`, filename: `${variant}.oci.tar` })) }),
    /immutable sha256 digest/,
    'mutable registry tags cannot enter the catalog',
  );
  await assert.rejects(
    () => verifyCatalog({ catalog, payloadDir, expectedArch: 'x86_64' }),
    /architecture mismatch/,
    'cross-architecture payload catalogs are rejected',
  );

  await writeFile(join(payloadDir, '../outside.oci.tar'), 'must not escape payload directory');
  const escaped = structuredClone(catalog);
  escaped.payloads[0].filename = '../outside.oci.tar';
  await assert.rejects(
    () => verifyCatalog({ catalog: escaped, payloadDir, expectedArch: 'aarch64' }),
    /unsafe payload filename/,
    'catalog filenames cannot escape the media payload directory',
  );

  await writeFile(join(payloadDir, 'cosmic.oci.tar'), 'altered after signing');
  await assert.rejects(
    () => verifyCatalog({ catalog, payloadDir, expectedArch: 'aarch64' }),
    /payload integrity mismatch: cosmic/,
    'post-catalog payload alteration is detected',
  );

  const unsigned = structuredClone(catalog);
  unsigned.payloads[1].signedIndex = `${imageRepositories.cosmic}:latest`;
  await assert.rejects(
    () => verifyCatalog({ catalog: unsigned, payloadDir, expectedArch: 'aarch64' }),
    /immutable sha256 digest: cosmic/,
    'a payload must name the immutable signed index it was exported from',
  );

  // The command line the workflow runs: build a catalog, then verify it.
  const cliDir = join(root, 'cli');
  await mkdir(cliDir);
  for (const variant of variants) await writeFile(join(cliDir, `${variant}.oci.tar`), `cli payload for ${variant}`);
  await writeFile(join(root, 'images.tsv'), images.map(({ variant, signedIndex, image, filename }) => [variant, signedIndex, image, filename].join('\t')).join('\n'));
  await catalogModule.main(['build', cliDir, 'x86_64', 'prototype-cli', join(root, 'images.tsv'), join(root, 'cli-catalog.json')]);
  await catalogModule.main(['verify', cliDir, 'x86_64', join(root, 'cli-catalog.json')]);
  await assert.rejects(
    () => catalogModule.main(['verify', cliDir, 'aarch64', join(root, 'cli-catalog.json')]),
    /architecture mismatch/,
    'the verify command rejects the other architecture',
  );

  const saved = await readFile(join(payloadDir, 'plasma.oci.tar'));
  assert.ok(saved.length > 0, 'catalog verification did not remove or rewrite payloads');
} finally {
  await rm(root, { recursive: true, force: true });
}

console.log('offline media prototype catalog contracts passed');
