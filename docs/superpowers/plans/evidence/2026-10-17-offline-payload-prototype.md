# Offline Installer Payload Prototype — Evidence and Gate

**Status:** payload format and offline trust chain proven; Anaconda handoff still to prove
**Date:** 2026-10-17 (results 2026-10-18)
**Plan:** [`../2026-10-17-stable-desktop-media.md`](../2026-10-17-stable-desktop-media.md)
**Variants:** Plasma and COSMIC. The Hyprland variant was retired after v0.5.9 ([ADR 0018](https://github.com/agentux-os/agentux/blob/main/docs/adr/0018-retire-the-hyprland-variant.md)).

## What was run

[`.github/workflows/offline-media-prototype.yml`](../../../../.github/workflows/offline-media-prototype.yml), the `payload and offline install` jobs, on GitHub's `ubuntu-24.04` (x86_64, KVM) and `ubuntu-24.04-arm` (aarch64) runners, from `:latest` of `ghcr.io/agentux-os/agentux` and `ghcr.io/agentux-os/agentux-cosmic`. Passing run: [39087251741](https://github.com/agentux-os/agentux-os/actions/runs/39087251741) (commit `56f82cc`). The job runs on demand (`workflow_dispatch`, or an `[offline-proof]` commit on the prototype branch); the catalog contract tests run on every PR that touches the prototype.

## Results

1. **Export keeps exactly what is signed.** build.yml signs each image's multi-architecture index (AgentUX key and keyless, main's `build.yml` identity). The job verifies both signatures on the index, takes the `linux/<arch>` manifest the index lists, exports that manifest by digest to an `oci-archive` with `--preserve-digests`, and fails unless the exported manifest has that digest. Both variants, both architectures: exported unchanged. An earlier run exported by tag with `--override-arch` and recorded a manifest digest that no signature covered; that is what this check now prevents.
2. **Catalog.** [`installer/offline-prototype/catalog.mjs`](../../../../installer/offline-prototype/catalog.mjs) records, per variant, the signed index, the exported manifest, the payload file, its size and sha256 (streamed: payloads are 3–4 GiB, over Node's 2 GiB `readFile` limit). Only the catalog is signed; it pins every payload, so the installer verifies the catalog's signature and then the selected payload's hash, offline. The prototype signs with a throwaway CI key, never a release key.
3. **Offline rejection.** Rejected without network: a catalog changed after signing (cosign), a payload that does not match the signed catalog (`payload integrity mismatch`), and the catalog of the other architecture. The contract tests also reject unsafe file names, mutable tags, missing variants and a payload without an immutable signed index.
4. **Offline install.** `bootc install to-disk --source-imgref=oci-archive:… --filesystem btrfs` from the Plasma payload, in a container with `--network=none`, onto a throwaway qcow2 disk: completed on both architectures in about 5–7 minutes. The disk holds an ostree deployment whose origin is `container-image-reference=ostree-unverified-registry:ghcr.io/agentux-os/agentux:stable`, so the installed system follows the stable channel. (Kinoite's image sets no default root filesystem; `bootc` needs `--filesystem`.)
5. **Size.** Layers are already compressed in the archives; recompressing them (the first draft used `zstd -19`) costs build time for little. The measure that matters is sharing between variants:

| Architecture | Separate archives | One shared OCI layout | Saved |
|---|---:|---:|---:|
| x86_64 | 6.91 GiB | 6.04 GiB | 0.87 GiB (13%) |
| aarch64 | 6.89 GiB | 5.86 GiB | 1.03 GiB (15%) |

   With three variants (Plasma and Hyprland both on Kinoite) a shared layout saved 37% (10.70 → 6.70 GiB on x86_64). Plasma and COSMIC have different bases, so the saving is small, but a shared layout is still smaller and is one directory instead of several archives. The current Plasma-only installer ISO is about 4.7 GiB (`agentux-v0.5.6-x86_64.iso`, 5,084,020,736 bytes); a two-desktop offline ISO would be roughly 6–7 GiB, which needs an 8 GB USB stick and no longer fits a single-layer DVD.

## Gate

- **Go** for the payload format (OCI, by digest, from the signed index), the catalog and its offline verification, and for building one offline installer per architecture from them.
- **Still to prove before Task 3:** the handoff inside the installer ISO. The test above uses bootc's own installer; the ISO goes through Anaconda (`ostreecontainer --transport=oci-archive` or `oci` with a local path), which has to be booted in a VM with networking off, choosing each desktop. That is Task 1's remaining step.
- **Decide in Task 2:** one shared OCI layout for both variants (smaller, one tree to verify) or one archive per variant (simpler to verify and extract one).
- **Check:** the installed origin says `ostree-unverified-registry`, the same as an install from the network; the containers policy (`/etc/containers/policy.json`, AgentUX key required) is what checks `bootc upgrade`, so this is expected, but Task 3 should confirm the first upgrade of an offline install still enforces it.

## Sources

- Anaconda/PyKickstart `ostreecontainer` transports: <https://github.com/rhinstaller/anaconda/discussions/5197>, <https://pykickstart.readthedocs.io/>.
- Repository installer configuration: [`disk_config/iso.toml`](../../../../disk_config/iso.toml); VM install harness: [`tests/iso-vm.sh`](../../../../tests/iso-vm.sh).
