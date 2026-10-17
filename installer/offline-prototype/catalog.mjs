import { createHash } from 'node:crypto';
import { readFile, stat, writeFile } from 'node:fs/promises';
import { basename, join } from 'node:path';
import { pathToFileURL } from 'node:url';

export const VARIANTS = Object.freeze(['plasma', 'hyprland', 'cosmic']);
const ARCHITECTURES = new Set(['x86_64', 'aarch64']);
const IMAGE_REPOSITORIES = Object.freeze({
  plasma: 'ghcr.io/agentux-os/agentux',
  hyprland: 'ghcr.io/agentux-os/agentux-hyprland',
  cosmic: 'ghcr.io/agentux-os/agentux-cosmic',
});

export function parseImageManifest(contents) {
  const rows = contents.trim().split(/\r?\n/);
  return rows.map((row) => {
    const [variant, image, filename, ...extra] = row.split('\t');
    if (!variant || !image || !filename || extra.length > 0) throw new Error('invalid image manifest row');
    return { variant, image, filename };
  });
}

function imageDigest(image, variant) {
  const repository = IMAGE_REPOSITORIES[variant];
  if (typeof image !== 'string' || !image.startsWith(`${repository}:`) && !image.startsWith(`${repository}@`)) {
    throw new Error(`image repository mismatch: ${variant}`);
  }
  const digest = image.slice(repository.length + 1);
  if (!/^sha256:[a-f0-9]{64}$/.test(digest)) {
    throw new Error(`image must use an immutable sha256 digest: ${variant}`);
  }
  return digest;
}

function safeFilename(filename) {
  return typeof filename === 'string'
    && filename.length > 0
    && basename(filename) === filename
    && !filename.includes('..')
    && /^[a-z0-9][a-z0-9._-]*\.oci\.tar\.zst$/.test(filename);
}

export async function buildCatalog({ payloadDir, arch, version, images }) {
  if (!ARCHITECTURES.has(arch)) throw new Error(`unsupported architecture: ${arch}`);
  if (typeof version !== 'string' || !/^(?:v[0-9][A-Za-z0-9.-]*|prototype-[A-Za-z0-9.-]+)$/.test(version)) {
    throw new Error('invalid release version');
  }
  if (!Array.isArray(images) || images.length !== VARIANTS.length
      || VARIANTS.some((variant) => images.filter((item) => item.variant === variant).length !== 1)) {
    throw new Error('catalog requires exactly plasma, hyprland, cosmic');
  }

  const payloads = [];
  for (const variant of VARIANTS) {
    const image = images.find((candidate) => candidate.variant === variant);
    const digest = imageDigest(image.image, variant);
    if (!safeFilename(image.filename)) throw new Error(`unsafe payload filename: ${variant}`);
    const path = join(payloadDir, image.filename);
    const [bytes, info] = await Promise.all([readFile(path), stat(path)]);
    payloads.push({
      variant,
      image: image.image,
      imageDigest: digest,
      filename: image.filename,
      size: info.size,
      sha256: createHash('sha256').update(bytes).digest('hex'),
    });
  }

  return { schemaVersion: 1, version, arch, variants: [...VARIANTS], payloads };
}

export async function verifyCatalog({ catalog, payloadDir, expectedArch }) {
  if (!catalog || catalog.schemaVersion !== 1) throw new Error('unsupported payload catalog schema');
  if (catalog.arch !== expectedArch) throw new Error(`architecture mismatch: expected ${expectedArch}, got ${catalog.arch}`);
  if (!Array.isArray(catalog.variants) || catalog.variants.length !== VARIANTS.length
      || VARIANTS.some((variant, index) => catalog.variants[index] !== variant)) {
    throw new Error('catalog variants must be exactly plasma, hyprland, cosmic in canonical order');
  }
  if (!Array.isArray(catalog.payloads) || catalog.payloads.length !== VARIANTS.length) {
    throw new Error('catalog must contain exactly three payloads');
  }

  for (const [index, variant] of VARIANTS.entries()) {
    const payload = catalog.payloads[index];
    if (payload?.variant !== variant) throw new Error(`payload order mismatch: ${variant}`);
    if (!safeFilename(payload.filename)) throw new Error(`unsafe payload filename: ${variant}`);
    if (imageDigest(payload.image, variant) !== payload.imageDigest) throw new Error(`image digest mismatch: ${variant}`);
    const bytes = await readFile(join(payloadDir, payload.filename));
    if (bytes.length !== payload.size
        || createHash('sha256').update(bytes).digest('hex') !== payload.sha256) {
      throw new Error(`payload integrity mismatch: ${variant}`);
    }
  }

  return { valid: true, variants: [...VARIANTS] };
}

async function main(args) {
  const [command, payloadDir, arch, version, manifestPath, catalogPath] = args;
  if (command === 'build' && payloadDir && arch && version && manifestPath && catalogPath) {
    const images = parseImageManifest(await readFile(manifestPath, 'utf8'));
    const catalog = await buildCatalog({ payloadDir, arch, version, images });
    await writeFile(catalogPath, `${JSON.stringify(catalog, null, 2)}\n`, { flag: 'wx' });
    return;
  }
  if (command === 'verify' && payloadDir && arch && manifestPath) {
    const catalog = JSON.parse(await readFile(manifestPath, 'utf8'));
    await verifyCatalog({ catalog, payloadDir, expectedArch: arch });
    return;
  }
  throw new Error('usage: catalog.mjs build PAYLOAD_DIR ARCH VERSION IMAGE_MANIFEST CATALOG | verify PAYLOAD_DIR ARCH CATALOG');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2)).then(() => {
    console.log('offline prototype catalog: ok');
  }).catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
