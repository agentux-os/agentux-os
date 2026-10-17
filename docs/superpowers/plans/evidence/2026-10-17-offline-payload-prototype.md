# Offline Installer Payload Prototype — Evidence and Gate

**Status:** incomplete; no implementation go decision  
**Date:** 2026-10-17  
**Plan:** [`../2026-10-17-stable-desktop-media.md`](../2026-10-17-stable-desktop-media.md)

## Findings from read-only inspection

1. The existing installer is already offline-capable for one image: `bootc-image-builder` embeds the selected container image, and its generated Anaconda kickstart uses `ostreecontainer`. `disk_config/iso.toml` documents that contract.
2. Anaconda's `ostreecontainer` transport supports a local OCI layout. The upstream Anaconda discussion describes `ostreecontainer --url=/mycontainerdir --transport=oci`; the current PyKickstart reference lists `registry`, `oci`, and `oci-archive` transports. This makes an OCI layout directory, compressed as a media payload and extracted only for the selected variant, a plausible prototype candidate. It is **not yet validated** with AgentUX images or the project's Anaconda build.
3. A plausible trust chain is to verify each OCI source digest/signature during release build, then sign the exact compressed media payload and catalog with the AgentUX media key. The offline installer would verify the signed catalog and selected payload before extraction, then let Anaconda consume the local OCI layout. This chain is only a hypothesis until end-to-end verification proves the identity binding and offline behavior.
4. The current public `latest.json` reports v0.5.6 Plasma x86_64 installer size **5,084,020,736 bytes** and aarch64 **4,998,758,400 bytes**. It does not include current per-variant Hyprland or COSMIC installer payload baselines, so a total-size comparison cannot be calculated from this manifest alone.
5. Existing x86_64 install validation is `tests/iso-vm.sh`: boot the ISO in QEMU/KVM, use its installer payload, reboot the installed disk, and run the installed-system checks. This harness must be extended to disable networking and choose each variant for the proposed installer.

## Blocked measurements

The end-to-end prototype and runner capacity measurements were not possible in this environment:

- Git Bash fails to launch with `CreateFileMapping ... Win32 error 5`.
- WSL reports `E_ACCESSDENIED` while enumerating distros.
- Docker CLI cannot connect to either configured Docker Engine named pipe (permission denied).
- `podman`, `skopeo`, `cosign`, `qemu-system-x86_64`, and `qemu-img` are not installed/available as Windows commands.
- `gh run list` cannot reach GitHub's API because the configured proxy at `127.0.0.1:9` refuses the connection.

Therefore there are no measured payload sizes, peak disk/RAM values, decompression/install timings, offline signature-verification results, or no-network VM installation results. No local build or remote workflow was started.

## Gate result

**No-go for implementation Tasks 2–4 until the prototype runs on a Linux environment with container, Cosign, and QEMU/KVM or TCG support.** The local OCI transport is technically plausible based on upstream Anaconda interfaces, but the approved plan requires a demonstrated signed-image export → compressed payload → offline verification → local Anaconda install path. Do not treat upstream interface documentation as proof of the full AgentUX workflow, and do not weaken the signature/offline requirements.

## Sources

- Current public manifest: <https://download.agentuxos.org/latest.json> (observed v0.5.6 during this investigation).
- Anaconda/PyKickstart `ostreecontainer` transport discussion: <https://github.com/rhinstaller/anaconda/discussions/5197>.
- PyKickstart command reference: <https://pykickstart.readthedocs.io/_/downloads/en/latest/pdf/>.
- Repository installer configuration: [`disk_config/iso.toml`](../../../../disk_config/iso.toml).
- Repository VM install harness: [`tests/iso-vm.sh`](../../../../tests/iso-vm.sh).
