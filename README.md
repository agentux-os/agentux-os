# agentux-os

The [AgentUX](https://github.com/agentux-os/agentux) Linux distribution image: a [bootc](https://containers.github.io/bootc/) image on Fedora Atomic (Kinoite, KDE Plasma), defined by a single `Containerfile` and built by CI.

> **Status:** bootstrapping. See [ADR 0001](https://github.com/agentux-os/agentux/blob/main/docs/adr/0001-linux-distribution-on-fedora-atomic.md) for the design.

## What the image contains

- **Base:** Fedora Kinoite — immutable `/usr`, atomic updates, previous image always bootable for rollback.
- **System toolchain:** `git`, `gh`, `ripgrep`, `fd`, `jq`, `bat`, `delta`, `just`, `uv`, Node.js, `mise`, Podman, Distrobox.
- **Coding agent CLIs:** Claude Code, Codex, OpenCode and Antigravity CLI, installed per user on first login so each can keep itself up to date.
- **AgentUX:** `agentuxd`, `aux` and the cockpit (once [agentux-core](https://github.com/agentux-os/agentux-core) and [agentux-desktop](https://github.com/agentux-os/agentux-desktop) ship).

## Install

### From the ISO

The [Build ISO](https://github.com/agentux-os/agentux-os/actions/workflows/iso.yml) workflow turns the latest image into an Anaconda installer ISO with [bootc-image-builder](https://github.com/osbuild/image-builder/tree/main/bootc-image-builder). Download `agentux-<date>-x86_64.iso` from the artifacts of a successful run, check it against the `.sha256` next to it, and write it to a USB stick:

```sh
sha256sum -c agentux-*.iso.sha256
sudo dd if=agentux-<date>-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

The installer is interactive: you pick the disk, language and time zone and create your account. The installed system tracks `ghcr.io/agentux-os/agentux:latest` and updates from it.

### From an existing Fedora Atomic or bootc system

Switch to the latest image:

```sh
sudo bootc switch ghcr.io/agentux-os/agentux:latest
systemctl reboot
```

Roll back with `sudo bootc rollback`.

## Build and test locally

You need Linux with Podman and [`just`](https://just.systems); `vm` also needs QEMU with KVM and OVMF.

```sh
just build        # podman build -> localhost/agentux:dev
just iso          # installer ISO from that image -> output/bootiso/install.iso (uses sudo)
just vm           # install the ISO into a VM disk, output/vm-disk.qcow2
just vm disk      # boot the installed VM disk
just lint         # shellcheck + hadolint, the same checks as CI
```

`just qcow2 path/to/config.toml` builds a ready-to-boot disk instead (`just vm qcow2` boots it); the config should add a user with `[[customizations.user]]`. Set `AGENTUX_IMAGE` to build from another image, e.g. `AGENTUX_IMAGE=ghcr.io/agentux-os/agentux:latest just iso` after a `podman pull`.

## License

[Apache 2.0](LICENSE)
