# agentux-os

The [AgentUX](https://github.com/agentux-os/agentux) Linux distribution image: a [bootc](https://containers.github.io/bootc/) image on Fedora Atomic (Kinoite, KDE Plasma), defined by a single `Containerfile` and built by CI.

> **Status:** bootstrapping. See [ADR 0001](https://github.com/agentux-os/agentux/blob/main/docs/adr/0001-linux-distribution-on-fedora-atomic.md) for the design.

## What the image contains

- **Base:** Fedora Kinoite — immutable `/usr`, atomic updates, previous image always bootable for rollback.
- **System toolchain:** `git`, `gh`, `ripgrep`, `fd`, `jq`, `bat`, `delta`, `just`, `uv`, Node.js, `mise`, Podman, Distrobox.
- **Coding agent CLIs:** Claude Code, Codex, OpenCode and Antigravity CLI, installed per user on first login so each can keep itself up to date.
- **AgentUX:** `agentuxd`, `aux` and the cockpit (once [agentux-core](https://github.com/agentux-os/agentux-core) and [agentux-desktop](https://github.com/agentux-os/agentux-desktop) ship).

## Try it

Switch an existing Fedora Atomic or bootc system to the latest image:

```sh
sudo bootc switch ghcr.io/agentux-os/agentux:latest
systemctl reboot
```

Roll back with `sudo bootc rollback`. An installable ISO is planned.

## Build locally

```sh
podman build -t agentux:dev .
```

## License

[Apache 2.0](LICENSE)
