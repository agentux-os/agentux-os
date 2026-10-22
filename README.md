<p align="center">
  <a href="https://agentuxos.org">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/agentux-os/agentux/main/brand/svg/lockup-dark.svg">
      <img alt="AgentUX" src="https://raw.githubusercontent.com/agentux-os/agentux/main/brand/svg/lockup-light.svg" width="340">
    </picture>
  </a>
</p>

<h3 align="center">agentux-os: the bootable, signed AgentUX system image</h3>

<p align="center">
  <a href="https://github.com/agentux-os/agentux-os/actions/workflows/build.yml"><img alt="Image build" src="https://img.shields.io/github/actions/workflow/status/agentux-os/agentux-os/build.yml?branch=main&label=image%20build&logo=github&labelColor=0b0d10"></a>
  <a href="https://github.com/agentux-os/agentux-os/actions/workflows/live.yml"><img alt="Live ISO" src="https://img.shields.io/github/actions/workflow/status/agentux-os/agentux-os/live.yml?branch=main&label=live%20ISO&labelColor=0b0d10"></a>
  <a href="https://github.com/agentux-os/agentux-os/pkgs/container/agentux"><img alt="Image on ghcr.io" src="https://img.shields.io/badge/ghcr.io-agentux--os%2Fagentux-4f7d0b?logo=podman&logoColor=c6f36b&labelColor=0b0d10"></a>
  <a href="https://fedoraproject.org/atomic-desktops/kinoite/"><img alt="Base: Fedora Kinoite 44" src="https://img.shields.io/badge/base-Fedora%20Kinoite%2044%20%C2%B7%20bootc-4f7d0b?logo=fedora&logoColor=white&labelColor=0b0d10"></a>
  <a href="#architectures"><img alt="Architectures" src="https://img.shields.io/badge/arch-x86__64%20%7C%20aarch64-4f7d0b?labelColor=0b0d10"></a>
  <a href="#verifying-the-image"><img alt="Signed with cosign" src="https://img.shields.io/badge/images-cosign%20signed-4f7d0b?labelColor=0b0d10"></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/github/license/agentux-os/agentux-os?labelColor=0b0d10&color=4f7d0b"></a>
  <a href="https://agentuxos.org"><img alt="Website" src="https://img.shields.io/badge/website-agentuxos.org-c6f36b?labelColor=0b0d10"></a>
  <a href="https://github.com/agentux-os/agentux-os/releases"><img alt="Release" src="https://img.shields.io/github/v/release/agentux-os/agentux-os?include_prereleases&label=release&labelColor=0b0d10&color=4f7d0b"></a>
  <a href="https://agentuxos.org/download/"><img alt="Download" src="https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fdownload.agentuxos.org%2Flatest.json&query=%24.version&label=download&labelColor=0b0d10&color=c6f36b&cacheSeconds=3600"></a>
</p>

<p align="center">
  <a href="https://agentuxos.org"><b>Website</b></a> ·
  <a href="https://download.agentuxos.org"><b>Download</b></a> ·
  <a href="https://github.com/agentux-os/agentux/tree/main/docs"><b>Docs</b></a> ·
  <a href="https://github.com/agentux-os/agentux/blob/main/docs/getting-started.md"><b>Getting started</b></a> ·
  <a href="https://github.com/agentux-os/agentux-os/releases"><b>Releases</b></a>
</p>

The [AgentUX](https://github.com/agentux-os/agentux) Linux distribution image: a [bootc](https://containers.github.io/bootc/) image on Fedora Atomic (Kinoite, KDE Plasma), defined by a single `Containerfile` and built by CI for **x86_64 (amd64) and aarch64 (arm64)**. It ships Claude Code, Codex, OpenCode and Antigravity CLI already wired together, with the AgentUX daemon, the `aux` CLI and the cockpit on top: one interface for every agent, an agent bus between them and an orchestrator that takes work from issue to reviewed pull request.

> **Status:** pre-release. The `:stable` channel and stable ISOs follow the latest approved image release; the nightly `:latest` channel moves automatically from `main`. The current version is exposed by the dynamic download badge and [`latest.json`](https://download.agentuxos.org/latest.json). See [ADR 0001](https://github.com/agentux-os/agentux/blob/main/docs/adr/0001-linux-distribution-on-fedora-atomic.md) for the design, and [Release channels](#release-channels) for what `:stable` and `:latest` mean.

## Current artifacts

This repository publishes the signed container images, installer ISOs and live ISOs automatically. The stable download paths below are intentionally version-free: the release workflow updates them when a release is approved, while the nightly paths are refreshed by the scheduled image/ISO workflows.

| Artifact | Current channel |
|---|---|
| KDE Plasma image | [`ghcr.io/agentux-os/agentux:stable`](https://github.com/agentux-os/agentux/pkgs/container/agentux) |
| COSMIC image | [`ghcr.io/agentux-os/agentux-cosmic:stable`](https://github.com/agentux-os/agentux/pkgs/container/agentux-cosmic) |
| KDE Plasma — live ISO | [`x86_64`](https://download.agentuxos.org/iso/stable/agentux-plasma-live-x86_64.iso) · [`aarch64`](https://download.agentuxos.org/iso/stable/agentux-plasma-live-aarch64.iso) |
| KDE Plasma — offline installer ISO | [`x86_64`](https://download.agentuxos.org/iso/stable/agentux-plasma-installer-x86_64.iso) · [`aarch64`](https://download.agentuxos.org/iso/stable/agentux-plasma-installer-aarch64.iso) |
| COSMIC — live ISO | [`x86_64`](https://download.agentuxos.org/iso/stable/agentux-cosmic-live-x86_64.iso) · [`aarch64`](https://download.agentuxos.org/iso/stable/agentux-cosmic-live-aarch64.iso) |
| COSMIC — offline installer ISO | [`x86_64`](https://download.agentuxos.org/iso/stable/agentux-cosmic-installer-x86_64.iso) · [`aarch64`](https://download.agentuxos.org/iso/stable/agentux-cosmic-installer-aarch64.iso) |
| Release metadata | [`latest.json`](https://download.agentuxos.org/latest.json) · [GitHub releases](https://github.com/agentux-os/agentux-os/releases/latest) |

| Boot | Live desktop | Installer |
|---|---|---|
| [<img alt="The penguin swimming in the boot splash" src="https://raw.githubusercontent.com/agentux-os/agentux/main/docs/screenshots/boot-animation.gif" width="260">](https://raw.githubusercontent.com/agentux-os/agentux/main/docs/screenshots/boot-animation.gif) | [<img alt="The live ISO desktop with the AgentUX cockpit running two demo runs" src="https://raw.githubusercontent.com/agentux-os/agentux/main/docs/screenshots/cockpit-runs.png" width="260">](https://raw.githubusercontent.com/agentux-os/agentux/main/docs/screenshots/cockpit-runs.png) | [<img alt="The AgentUX installer on the live ISO" src="https://raw.githubusercontent.com/agentux-os/agentux/main/docs/screenshots/installer.png" width="260">](https://raw.githubusercontent.com/agentux-os/agentux/main/docs/screenshots/installer.png) |

<sub>Captured by CI: the live ISO and installer tests boot the real images in QEMU; the demo runs use fake agents.</sub>

## Quick start

**1. Try it live, without installing.** Download the live ISO, check it and write it to a USB stick (or attach it to a UEFI VM with 4 GB of RAM or more):

```sh
curl -LO https://download.agentuxos.org/iso/stable/agentux-plasma-live-x86_64.iso
curl -LO https://download.agentuxos.org/iso/stable/agentux-plasma-live-x86_64.iso.sha256
sha256sum --check agentux-plasma-live-x86_64.iso.sha256
```

It boots into the real desktop with a demo of fake agents, and an **Install AgentUX** launcher when you want to keep it ([Try it live](#try-it-live)). Every ISO is named `agentux-<desktop>-<live|installer>-<version>-<arch>.iso`: pick the desktop (`plasma` or `cosmic`), `live` to try it first (installing from it needs internet) or `installer` to install offline, and `x86_64` for PCs or `aarch64` for 64-bit ARM ([Install](#install), [Downloads](#downloads)).

**2. Or switch an existing Fedora Atomic / bootc system:**

```sh
sudo bootc switch ghcr.io/agentux-os/agentux:stable            # KDE Plasma
sudo bootc switch ghcr.io/agentux-os/agentux-cosmic:latest     # COSMIC nightly
systemctl reboot
```

Use `:latest` instead of `:stable` for the nightly builds ([Release channels](#release-channels)); `sudo bootc rollback` takes you back.

**3. After the first login,** follow [Getting started](https://github.com/agentux-os/agentux/blob/main/docs/getting-started.md): log in to the vendor CLIs, take the cockpit tour and start a first run. Every image is signed, and installed systems refuse unsigned updates ([Verifying the image](#verifying-the-image)).

## Contents

- **Use it:** [Variants](#variants) · [Architectures](#architectures) · [Release channels](#release-channels) · [Install](#install) · [Try it live](#try-it-live) · [Downloads](#downloads) · [Verifying the image](#verifying-the-image)
- **What's inside:** [What the image contains](#what-the-image-contains) · [Identity](#identity) · [Version](#version) · [Default wallpaper](#default-wallpaper) · [AgentUX versions](#agentux-versions) · [Boot splash](#boot-splash) · [GRUB menu](#grub-menu)
- **Work on it:** [Build and test locally](#build-and-test-locally) · [Boot test](#boot-test) · [Live ISO test](#live-iso-test) · [Installer ISO test](#installer-iso-test) · [How a release reaches `:stable`](#how-a-release-reaches-stable) · [License](#license)

Deep reference detail is folded away in collapsible sections; click a summary to expand it.

## Variants

The one `Containerfile` builds two images, chosen by the build argument `VARIANT`:

| Image | `VARIANT` | Desktop |
|---|---|---|
| `ghcr.io/agentux-os/agentux` | `plasma` (default) | KDE Plasma, the AgentUX defaults described below |
| `ghcr.io/agentux-os/agentux-cosmic` | `cosmic` | Fedora COSMIC Atomic with AgentUX integration; no Plasma session or overlay |

Both are multi-arch, signed and checked against the AgentUX key. Both are released: each release ships a live and an offline installer ISO of each, for both architectures. Switching between Plasma and COSMIC with `bootc switch` is not a supported path yet: install the one you want.

## Architectures

`ghcr.io/agentux-os/agentux` is a multi-arch image: each tag is a manifest list with a `linux/amd64` and a `linux/arm64` image, and `podman pull`, `bootc switch` and `bootc upgrade` pick the one for the machine they run on. CI builds each natively (GitHub's `ubuntu-24.04` and `ubuntu-24.04-arm` runners, no emulation) from the same `Containerfile`, which installs the AgentUX RPMs for the build's architecture (`uname -m`). The arm64 image targets UEFI machines that Fedora supports on aarch64 (SystemReady servers and workstations, VMs on Apple silicon or Ampere hosts); boards that need their own firmware or kernel are not covered.

## Release channels

Each image repository has two channels, and an installed system follows exactly one of them:

| Tag | Channel | Moves |
|---|---|---|
| `:stable` | **Stable**: the newest release | When the owner approves a `v*` tag, to that tag's image |
| `:v<version>` (e.g. `:v0.5.5`) | One release | Never: set once, when its release is approved |
| `:latest` | **Nightly** (testing): `main`, rebuilt daily for Fedora's updates | Every day, and on every merge to `main` |
| `:<YYYYMMDD>` | One nightly build | Never |

Stable and nightly channels exist for both images. Both repositories are multi-arch and require the same AgentUX image signature ([Verifying the image](#verifying-the-image)).

**Which channel a system follows** is the image reference in its origin, shown by `sudo bootc status`, and `bootc upgrade` pulls whatever that tag points at:

- Systems installed from a **release ISO** (`iso/stable/` or `iso/v<version>/` on download.agentuxos.org, or the links in a GitHub release) follow `:stable`.
- Systems installed from a **nightly ISO** (`iso/nightly/`), and every system installed before the channels existed (all installs so far), follow `:latest`. Nothing moves them: they stay on the nightly channel until you switch.

### Updates

Installed systems update themselves in the background and **never reboot on their own** (ADR 0019 in agentux-os/agentux). `agentux-update.timer` runs [`stage-update`](files/usr/libexec/agentux/stage-update) ten minutes after boot and then daily: `bootc upgrade` without `--apply` downloads the channel's new image and stages it for the next boot, which happens whenever you restart. It does nothing on a metered connection, nor on battery below 30% (`AGENTUX_UPDATE_MIN_BATTERY`). Each run writes `/var/lib/agentux/update-status.json`, readable by everyone, with the booted and staged images (and their release names when known), so the cockpit can say an update is waiting.

```sh
sudo systemctl start agentux-update.service      # stage now
cat /var/lib/agentux/update-status.json          # what is staged
sudo systemctl disable --now agentux-update.timer  # no background updates; `sudo bootc upgrade` still works
```

`bootc-fetch-apply-updates.timer`, which reboots to apply, stays off.

Switch channels at any time, either way:

```sh
sudo bootc switch ghcr.io/agentux-os/agentux:stable   # releases only
sudo bootc switch ghcr.io/agentux-os/agentux:latest   # nightly builds
systemctl reboot
```

Going from `:latest` to `:stable` usually moves to an older image, since a release is a nightly build from some days or weeks earlier; that is fine on an image-based system, and `sudo bootc rollback` returns to the previous deployment. Until the first release is approved there is no `:stable` (`bootc switch` to it fails with "manifest unknown"), so stay on `:latest` until then; the ISO workflows fall back to `:latest` too if asked for `:stable` before it exists.

### How a release reaches `:stable`

<details>
<summary>The five steps, and how to cut a release</summary>

Pushing a `v*` tag of a commit on `main` runs [`release.yml`](.github/workflows/release.yml):

Build once, promote: a release builds no image. It ships the digest that `main` already built, smoke-tested, signed and published for the tagged commit, so `:stable` is exactly what was tested, not a rebuild that would pull newer Fedora packages.

1. **Candidate.** The tag must be on `main`, and `main` must have published `sha-<commit>` for it: [`build.yml`](.github/workflows/build.yml) tags every `main` build `sha-<first 12 hex of the commit>` (with the dated tag and `:latest`) only after the smoke tests passed and the signatures were checked against the shipped policy. Both images are resolved once to their digests, and their AgentUX-key and keyless signatures (from `build.yml` on `main`) are checked. Tag a commit whose `Build image` run on `main` has finished; the nightly rebuild of an unchanged `main` moves `sha-<commit>` to the newer build of that commit.
2. **Boot test.** That Plasma digest is installed to a disk and booted in QEMU/KVM ([`boot.yml`](.github/workflows/boot.yml), called by `release.yml`), and `tests/boot.sh` runs on it.
3. **ISOs.** The installer and live ISOs (Plasma, x86_64 and aarch64) are built from the same digest and set up to follow `:stable`; the x86_64 ones are installed in a VM. ISOs are only built by releases and the weekly ISO runs. A release ISO installs that digest itself (not whatever a tag points at by then), so it installs exactly what was tested and released, and the installed system then follows `:stable`.
4. **Approval.** The `release` job waits in the `release` [environment](https://docs.github.com/actions/deployment/targeting-different-environments/using-environments-for-deployment), which only `v*` tags can use and which needs the repository owner's approval. Approving it is the last step, after every test of the tag passed. Rejecting it, or letting it time out, publishes nothing. Approve within 14 days: the release job publishes the ISO artifacts the run built and tested, which expire then (re-run the workflow after that).
5. **Promotion and publishing.** On approval, `:<tag>` and `:stable` of both images are pointed at the candidate digests ([`.github/scripts/promote.sh`](.github/scripts/promote.sh): a copy of the signed manifest list with its digest preserved, so the signatures, which are stored by digest, carry over; the key and keyless signatures are verified again on the new tags and on each architecture's image). Then the ISOs go to `iso/<tag>/` and `iso/stable/` on download.agentuxos.org, and the GitHub release is created.

To cut and approve a release from a terminal (Git Bash on Windows works too; needs `gh` logged in as the owner):

```sh
scripts/release.sh 0.5.2   # checks main's sha-<commit> images exist, shows the changes, pushes v0.5.2
scripts/approve.sh         # after the tests pass: shows the waiting run, asks, approves it
```

(`just release 0.5.2` and `just approve` run the same.) A version is never re-tagged: if a release run fails, fix it on `main` and tag the next patch version.

</details>

### Signing and approval: what the gate does and does not do

<details>
<summary>What the approval gates, and what the key can still sign</summary>

One AgentUX key signs every image, nightly or release, and installed systems' policy accepts any image in the AgentUX repositories signed with it, whatever its tag: `containers/image` checks signatures per repository and by digest, and cosign signs digests, not tags. The nightly channel must stay signed with that key (every installed system so far follows `:latest` and refuses anything else), so the key cannot move behind the approval: build.yml signs every build of `main` with it, and stays a repository secret (`COSIGN_PRIVATE_KEY`, `COSIGN_PASSWORD`).

So the approval gates **what the stable channel and the downloads point at**, not what the key can sign:

- Nothing reaches `:stable`, `:v<version>`, `iso/stable/`, `iso/v<version>/` or a GitHub release without the owner approving that tag's run, after its tests; a tag that is not on `main` fails before that.
- Writing to download.agentuxos.org needs the R2 credentials, which belong in the environments, not the repository: the `release` environment (approved `v*` tags) for releases and the `nightly` environment (only `main`, no approval) for the weekly ISOs, so a workflow run from any other branch cannot write to the bucket.
- Anyone who can run a workflow with the repository secrets (a collaborator with write access, from any branch) can still have an image signed with the key, and every installed system, on either channel, would accept that image if it were pushed to a tag the system follows. The key is the root of trust for both channels; protecting it is protecting all of them. Pull requests from forks get no secrets, so the key is as safe as the set of people and tokens with write access to this repository.

Two stronger options were left for later, since each needs every installed system to take a new policy first: a separate **release key**, required only for `:stable` (containers-policy.json can scope a requirement to `repository:tag`), held only in the `release` environment; or the image key itself moved into an environment limited to `main` and `v*` tags (no reviewers, so nightly signing keeps working), which would end keyed signing of branch test builds (`gh workflow run build.yml --ref <branch>`).

</details>

## Installation profiles

The image is role-neutral. The installer may seed a profile, which the first
boot applies through `agentux-profile-apply.service`; existing installs can
change it with `agentux profile apply <profile>`. The profiles are
`workstation` (node plus desktop), `node` (remote execution), `command`
(guarded Command server capability), `executive` (Office client), `complete`,
and `custom`. See the shipped [profile guide](files/usr/share/agentux/profiles/README.md).

The Command profile never layers PostgreSQL, NATS or object storage
into the immutable host. It requires explicit image/configuration and leaves
the future Quadlet bundle under the Command product's ownership.

## Install

### From the ISO

The [Build ISO](https://github.com/agentux-os/agentux-os/actions/workflows/iso.yml) workflow turns an image (a release's, or the nightly `:latest`) into an Anaconda installer ISO per architecture with [bootc-image-builder](https://github.com/osbuild/image-builder/tree/main/bootc-image-builder), one per desktop and architecture, each built natively: `agentux-<desktop>-installer-<version>-<arch>.iso`, `x86_64` for PCs and `aarch64` for 64-bit ARM UEFI machines. Download the one for your machine from **[download.agentuxos.org/iso/stable/](https://download.agentuxos.org/iso/stable/)** (e.g. `agentux-plasma-installer-x86_64.iso`) or a [release](https://github.com/agentux-os/agentux-os/releases), check it against the `.sha256` next to it (see [Downloads](#downloads)), and write it to a USB stick:

```sh
sha256sum -c agentux-*.iso.sha256
sudo dd if=agentux-plasma-installer-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

On ARM, boot the aarch64 ISO through the machine's UEFI firmware (or attach it as the CD of an aarch64 UEFI VM, e.g. UTM or Parallels on Apple silicon, or QEMU with `qemu-efi-aarch64`/`edk2-aarch64`).

The installer is interactive: you pick the disk, language and time zone and create your account. The image is on the ISO, so it installs offline. A release ISO's installed system follows `ghcr.io/agentux-os/agentux:stable` and updates from it, a nightly ISO's `:latest` ([Release channels](#release-channels)). bootc-image-builder names the image it was given in the installed system's origin, so `iso.yml` hands it the image tagged as the channel (a release's digest, tagged `:stable` in the build's local storage).

The installer is AgentUX's: bootc-image-builder assembles its environment from Fedora's packages (`fedora-logos`, `fedora-release`), so out of the builder its Anaconda shows Fedora's logo and blue, its boot menu says "Install AgentUX 44" and the volume is labelled `Fedora-S-dvd-x86_64-44`, and its configuration offers no logo, product name or theme. [`installer/brand-iso.sh`](installer/brand-iso.sh) then gives the ISO Anaconda's own product branding mechanism, an `images/product.img` that Anaconda's initramfs unpacks over the installer environment before Anaconda starts: AgentUX's stylesheet and art ([`installer/product/`](installer/product), drawn by [`installer/build.py`](installer/build.py)) in place of the files Fedora's profile loads, and a `.buildstamp` naming the product `AgentUX <release>` (or `AgentUX nightly`). It also relabels the volume `AgentUX-<release>-<arch>` and renames the boot menu entries ("Install AgentUX v0.5.3"), on the ISO and in its EFI boot image, and implants the media check checksum again. What the ISO installs does not change: the embedded signed image and bootc-image-builder's kickstart stay as they are (ADR 0012 in agentux-os/agentux).

### From an existing Fedora Atomic or bootc system

Switch to the stable channel (or `:latest` for the nightly builds, see [Release channels](#release-channels)):

```sh
sudo bootc switch ghcr.io/agentux-os/agentux:stable
systemctl reboot
```

The same command works on x86_64 and aarch64: the tag is a manifest list and bootc pulls the image for the running architecture. Roll back with `sudo bootc rollback`.

## Try it live

The [Live ISO](https://github.com/agentux-os/agentux-os/actions/workflows/live.yml) workflow builds a live ISO: boot it from a USB stick or in a VM and AgentUX runs from RAM, without touching the disk, and installs from there when you want to keep it. Download the newest release from **[download.agentuxos.org/iso/stable/agentux-plasma-live-x86_64.iso](https://download.agentuxos.org/iso/stable/agentux-plasma-live-x86_64.iso)** ([`.sha256`](https://download.agentuxos.org/iso/stable/agentux-plasma-live-x86_64.iso.sha256)), a given one from the [releases](https://github.com/agentux-os/agentux-os/releases), or the newest weekly build from `iso/nightly/` (see [Downloads](#downloads)), check it against its `.sha256` (see [Downloads](#downloads)) and write it to a USB stick as above. Each run also keeps its ISO as an artifact for 14 days (`agentux-<desktop>-live-<date>-<arch>`; `arm64` an aarch64 ISO, which CI builds but cannot boot-test). It boots with UEFI (no legacy BIOS); give a VM at least 4 GB of RAM, 8 GB is comfortable.

What you get:

- **The real desktop.** The live system is the published image plus a thin live layer: GRUB's "Try or install AgentUX" entry logs a passwordless `liveuser` straight into Plasma (or COSMIC on the COSMIC ISO) with the AgentUX theme, wallpaper, panel and cockpit, as on an installed system.
- **A demo with fake agents.** Agent CLIs need vendor logins, so the live session's `agentuxd` runs with `--fake-agents`, a scripted stand-in that answers every agent step. At login it sets up `~/agentux-demo`, a small project whose `agentux.yaml` mirrors the default pipeline (Claude Code plans, OpenCode implements, Codex reviews), and starts two runs: one already approved, which runs through the gate and review to its pull request, and "Add a /health endpoint", which waits in the cockpit's inbox for you to approve its plan. A note on the desktop explains it; `aux ps` and `aux watch <run>` work in a terminal too.
- **No downloads at login.** On an installed system first login downloads the agent CLIs and Antigravity's ACP server (together over 1 GB); live, they would sit in RAM. The live session does not start `agentux-first-login.service` at login: **Try the agent CLIs in this session**, in the application menu, starts it on demand (into RAM, gone at reboot; the desktop has only **Install AgentUX**, so there is one "Install" icon). `agentux-antigravity-acp.service` never runs live (a drop-in adds `ConditionKernelCommandLine=!rd.live.image`).
- **Install AgentUX** (desktop, panel and menu) opens Anaconda's web installer, in AgentUX's colours with the mark in its title bar. You pick the language, keyboard and disk; the account is created by the first-boot wizard (plasma-setup) when the installed system starts, as on Fedora Kinoite. It installs the AgentUX image **from the registry** (`agentux-cosmic` from the COSMIC ISO), so it needs an internet connection (the launcher checks first and says so; use the installer ISO to install offline): a release ISO installs its release's image by digest, exactly what was tested and released, and leaves the system following `:stable`; a nightly ISO installs `:latest` and follows it (see [Release channels](#release-channels); `live.yml` passes both references to the live layer as `INSTALL_IMAGE` and `TRACK_IMAGE`). The pull goes through the image's own signature policy, so only an image signed with the AgentUX key installs, and the installed system tracks its channel exactly as one installed from the installer ISO (`bootc switch --mutate-in-place --transport registry`, as bootc-image-builder's installer does). Nothing from the live session is installed: it is not the live root that gets copied.

<details>
<summary>How the live ISO is built</summary>

How it is built: [`live/Containerfile`](live/Containerfile) starts from the published image and runs [`live/build.sh`](live/build.sh), which adds everything live-only; [Titanoboa](https://github.com/ublue-os/titanoboa) (Universal Blue's live ISO builder, used for Bazzite's and Bluefin's live ISOs) squashes that image into `LiveOS/squashfs.img` and writes the ISO with its kernel, initramfs and the GRUB entries from `/usr/lib/bootc-image-builder/iso.yaml`. Titanoboa's ISO boots UEFI only, so on x86_64 [`live/bios-iso.sh`](live/bios-iso.sh) then adds legacy BIOS boot the way Fedora's own media do it: GRUB's i386-pc El Torito image (made by the live image's `grub2-mkimage`) as the first boot entry, its modules in `/boot/grub2/i386-pc`, and GRUB's hybrid MBR (`boot_hybrid.img`), so a CD/DVD and a USB stick written with `dd` boot on BIOS. BIOS GRUB reads the same `/boot/grub2/grub.cfg` as the UEFI menu (same entries and kernel arguments); the EFI partition, shim (Secure Boot) and the volume label stay as Titanoboa wrote them. The live layer:

- regenerates the initramfs with dracut's `dmsquash-live` (the AgentUX boot splash stays in it), boots with `rd.live.image` and SELinux permissive (the squashfs carries no labels), and mounts a larger tmpfs on `/var/tmp`;
- adds `livesys-scripts` (the live user, autologin, Fedora's live tweaks), `anaconda-live` with an AgentUX profile and the payload in `/usr/share/agentux/live/install.ks`, and `qemu-guest-agent`;
- brands the web installer: anaconda-webui runs in Cockpit, which takes its logo and colours from `/usr/share/cockpit/branding/<ID>-<VARIANT_ID>/` before `branding/fedora/`, so [`live/cockpit-branding/`](live/cockpit-branding/) goes there (`fedora-agentux` or `fedora-agentux-cosmic`): the compact mark in Lime, an Ink title bar instead of Fedora's blue, Lime buttons on the dark theme and Moss on the light one. The product name in the title bar is os-release's `PRETTY_NAME`, already AgentUX's;
- replaces Fedora's "Install to Hard Drive" with **Install AgentUX** (the only desktop icon), adds **Try the agent CLIs in this session** to the application menu, pins Install AgentUX first in the panel and adds the desktop note;
- runs `agentuxd` with `--fake-agents` (a drop-in on its user unit) and enables `agentux-live-demo.service`;
- disables `agentux-first-login.service` and `agentux-antigravity-acp.service` for all users.

Live mode is visible to scripts as `rd.live.image` on the kernel command line, and `/usr/share/agentux/live/marker` exists only in the live layer. None of it is in the image: an installed system has none of these files.

</details>

## Downloads

ISOs are published on **download.agentuxos.org**, a Cloudflare R2 bucket: GitHub limits release files to 2 GiB and every ISO is larger (the installer about 4.7 GB, the live ISO about 3.7 GB). [`.github/scripts/publish-iso.sh`](.github/scripts/publish-iso.sh) uploads them, only after every ISO of the run built and the x86_64 live ISO passed its boot and install test:

| Path | What | Installs and follows |
|---|---|---|
| `iso/stable/agentux-<desktop>-<live\|installer>-<arch>.iso` | The newest release: Plasma and COSMIC, live and installer, x86_64 and aarch64 | the desktop's `:stable` |
| `iso/v<version>/…-v<version>-<arch>.iso` | Every release, kept; its [GitHub release](https://github.com/agentux-os/agentux-os/releases) carries the checksums and the links | `:stable` |
| `iso/nightly/agentux-<desktop>-<live\|installer>-<arch>.iso` | The newest weekly build (Plasma), or a run dispatched with **publish** from `main` (either desktop); replaced each time | the desktop's `:latest` |

Releases are published by [`release.yml`](.github/workflows/release.yml) after the owner approves the tag (see [How a release reaches `:stable`](#how-a-release-reaches-stable)); the weekly builds by the `publish` job of [`iso.yml`](.github/workflows/iso.yml) and [`live.yml`](.github/workflows/live.yml). A nightly copy's `x-amz-meta-build` header names the dated build it came from.

R2 serves objects, not directories, so every directory has an `index.html` listing what is there ([`.github/scripts/download-index.sh`](.github/scripts/download-index.sh), rebuilt after every publish), and a URL rewrite rule on the `agentuxos.org` zone (Transform Rules, `http_request_transform`) serves `<path>/index.html` for any `download.agentuxos.org/<path>/`. Browse [download.agentuxos.org/iso/](https://download.agentuxos.org/iso/).

Next to every ISO is `<name>.iso.sha256` (naming the file next to it) and `<name>.iso.sha256.sigstore.json`, a cosign signature of the checksum with the key that signs the images:

```sh
sha256sum --check agentux-plasma-live-x86_64.iso.sha256
cosign verify-blob --key files/etc/pki/containers/agentux-os.pub   --bundle agentux-plasma-live-x86_64.iso.sha256.sigstore.json agentux-plasma-live-x86_64.iso.sha256
```

Every directory also has **`SHA256SUMS`**, the checksums of all its ISOs in one file, signed the same way (`SHA256SUMS.sigstore.json`). It is rebuilt from the directory's `.sha256` files after every upload (the ISOs of a directory come from separate jobs), so it always lists what is there:

```sh
cosign verify-blob --key files/etc/pki/containers/agentux-os.pub --bundle SHA256SUMS.sigstore.json SHA256SUMS
sha256sum --check --ignore-missing SHA256SUMS
```

<details>
<summary><code>latest.json</code> and the bucket's credentials</summary>

**[`latest.json`](https://download.agentuxos.org/latest.json)** (with `latest.json.sigstore.json`) describes the newest release for the website's download buttons; it is rewritten, last, whenever the stable channel moves:

```json
{
  "version": "v0.6.0",
  "date": "2026-10-20T12:00:00Z",
  "channel": "stable",
  "release_notes": "https://github.com/agentux-os/agentux-os/releases/tag/v0.6.0",
  "sha256sums": "https://download.agentuxos.org/iso/v0.6.0/SHA256SUMS",
  "sha256sums_signature": "https://download.agentuxos.org/iso/v0.6.0/SHA256SUMS.sigstore.json",
  "public_key": "https://raw.githubusercontent.com/agentux-os/agentux-os/main/files/etc/pki/containers/agentux-os.pub",
  "images": {
    "plasma": {"ref": "ghcr.io/agentux-os/agentux:v0.6.0", "channel": "ghcr.io/agentux-os/agentux:stable", "digest": "sha256:..."},
    "cosmic": {"ref": "ghcr.io/agentux-os/agentux-cosmic:v0.6.0", "channel": "ghcr.io/agentux-os/agentux-cosmic:stable", "digest": "sha256:..."}
  },
  "isos": [
    {
      "name": "agentux-plasma-live-v0.6.0-x86_64.iso",
      "url": "https://download.agentuxos.org/iso/v0.6.0/agentux-plasma-live-v0.6.0-x86_64.iso",
      "stable_url": "https://download.agentuxos.org/iso/stable/agentux-plasma-live-x86_64.iso",
      "size": 3712345678,
      "sha256": "...",
      "arch": "x86_64",
      "kind": "live",
      "variant": "plasma",
      "channel": "stable",
      "boot_tested": true
    }
  ]
}
```

`isos` lists live before installer and x86_64 before aarch64; `kind` is `live` or `installer`, `size` is in bytes, and `boot_tested` says whether CI booted and installed that ISO before publishing it. A page on another origin that fetches it from the browser needs a CORS rule on the bucket allowing `GET` from that origin.

The bucket is written with the secrets `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID` and `R2_SECRET_ACCESS_KEY` (an R2 API token with Object Read & Write on `agentux-downloads` only). They belong in the `release` and `nightly` environments, not the repository, so only an approved release or a run on `main` can write the bucket (see [Signing and approval](#signing-and-approval-what-the-gate-does-and-does-not-do)); the publishing jobs read them from their environment, and fall back to repository secrets of the same name while those still exist.

</details>

## Verifying the image

Every image CI publishes is signed twice with [cosign](https://github.com/sigstore/cosign) before any public tag (`:latest`, a dated tag, `:stable`, `:v<version>`) moves to it, on every digest it publishes: the manifest list and the amd64 and arm64 images in it (a system checks the signature of the image for its architecture, not the list's):

- **keyless**, with the GitHub Actions identity of the build workflow on `main`, or at the release's tag for a release (Fulcio certificate, recorded in the Rekor transparency log);
- with the **AgentUX signing key**, whose public half is in this repository and in the image at [`/etc/pki/containers/agentux-os.pub`](files/etc/pki/containers/agentux-os.pub).

Check either from any machine:

```sh
cosign verify ghcr.io/agentux-os/agentux:latest \
  --certificate-identity-regexp '^https://github\.com/agentux-os/agentux-os/\.github/workflows/build\.yml@refs/heads/main$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

cosign verify ghcr.io/agentux-os/agentux:stable \
  --certificate-identity-regexp '^https://github\.com/agentux-os/agentux-os/\.github/workflows/build\.yml@refs/tags/v' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

cosign verify --key files/etc/pki/containers/agentux-os.pub ghcr.io/agentux-os/agentux:latest
```

That checks the list. To check one architecture's image, verify its digest from the list, e.g. for arm64:

```sh
digest="$(skopeo inspect --raw docker://ghcr.io/agentux-os/agentux:latest \
  | jq -r '.manifests[] | select(.platform.architecture == "arm64") | .digest')"
cosign verify --key files/etc/pki/containers/agentux-os.pub "ghcr.io/agentux-os/agentux@$digest"
```

### On installed systems

An installed system checks the key signature itself on every `bootc upgrade` and `bootc switch`, because the image ships:

- `/etc/containers/policy.json` adds three entries to Fedora's, in every image: `ghcr.io/agentux-os/agentux`, `ghcr.io/agentux-os/agentux-cosmic` and the retired `ghcr.io/agentux-os/agentux-hyprland` each require a `sigstoreSigned` signature by `/etc/pki/containers/agentux-os.pub` (identity `matchRepository`, since cosign signs repositories, not tags). Every other registry keeps Fedora's rules, including the `insecureAcceptAnything` default.
- `/etc/containers/registries.d/agentux-os.yaml`, which turns on `use-sigstore-attachments` for `ghcr.io/agentux-os` so the signature is fetched from the registry.

An update that is unsigned or signed by another key is refused before any layer is downloaded, and the system stays on what it runs. The policy checks the key signature, not the keyless one: containers/image only matches Fulcio certificates by e-mail, and GitHub Actions certificates carry a workflow URI.

Systems installed from an image older than the signing change have no such policy yet. Nothing special is needed: the next `sudo bootc upgrade` brings an image with the policy (that one pull is not checked), and every pull after it is. If you changed `/etc/containers/policy.json` yourself, `/etc` keeps your version on updates; check that the entry is there:

```sh
jq '.transports.docker["ghcr.io/agentux-os/agentux"]' /etc/containers/policy.json
```

and add it by hand if it is not. Do not use `bootc switch --enforce-container-sigpolicy`: it refuses any policy whose default is `insecureAcceptAnything`, which Fedora's is; the per-repository entry above is what enforces the signature.

<details>
<summary>How CI checks the signatures, and where the key lives</summary>

CI checks the policy the same way a system would: after signing, it runs the image's own `skopeo` with the image's own policy, registries.d and key ([`tests/sigpolicy.sh`](tests/sigpolicy.sh)), once per architecture (`skopeo --override-arch`, so it picks that architecture's image from the list as a system of that architecture would), against the signed list's digest and tag, which must pass, against an unsigned image pushed to `:ci-unsigned` in the same repository, which must be refused for lack of a signature, and against an image from another registry, which must still pass; it also checks that the policy requires the AgentUX key for both repositories. This runs for each variant's repository (`publish (plasma, agentux)`, `publish (cosmic, agentux-cosmic)`). If any of that fails, neither `:latest` nor the dated tag moves: each architecture's image is pushed first under a staging tag (`ci-staging-amd64`, `ci-staging-arm64`), the list under `ci-staging`, and the public tags are copied from the list's digest, unchanged, only after every check passed. To try the publishing path from a branch, run `gh workflow run build.yml --ref <branch>`: it pushes, signs and checks `test-<sha>` (the list) and `test-<sha>-amd64` / `test-<sha>-arm64` only. A `v*` tag (through `release.yml`) does the same with `candidate-<tag>`, and only the approved release job moves `:<tag>` and `:stable` to it.

The required check, `build`, passes when both variants built for both architectures and, outside pull requests, both lists were published; the per-image jobs are `image (plasma, amd64)`, `image (plasma, arm64)`, `image (cosmic, amd64)` and `image (cosmic, arm64)`, and the smoke tests `smoke (<variant>, <arch>)`.

Every job that builds or pulls an image first pulls it with [`.github/scripts/pull.sh`](.github/scripts/pull.sh), which retries up to five times with a growing pause: quay.io's CDN drops a blob download halfway now and then (`writing blob: ... unexpected EOF`), and podman's own few quick retries used to give up and fail the whole build. `podman build` then starts from the local copy of the base image.

The signing key lives in the repository secrets `COSIGN_PRIVATE_KEY` and `COSIGN_PASSWORD` (why it is not behind the release approval: [Signing and approval](#signing-and-approval-what-the-gate-does-and-does-not-do)). Rotating it means shipping the new public key in an image signed with the old one first (a `keyPaths` list with both), then switching CI to the new key.

</details>

## What the image contains

- **Base:** Fedora Kinoite — immutable `/usr`, atomic updates, previous image always bootable for rollback.
- **System toolchain:** `git`, `gh`, `ripgrep`, `fd`, `jq`, `bat`, `delta`, `just`, `uv`, Node.js, `mise`, Podman, Distrobox.
- **Coding agent CLIs:** Claude Code, Codex, OpenCode and Antigravity CLI, plus their [ACP](https://agentclientprotocol.com) adapters, installed per user on first login so each can keep itself up to date (`agentux-first-login.service` waits for NetworkManager to be online and, if a download fails, retries every 5 minutes, at most 4 times per hour, then again on the next login). Every step has a time budget (5 minutes per CLI) and every download a connect timeout and stall detection, and the unit's `TimeoutStartSec` (35 minutes) bounds the whole run, so a stuck server or vendor installer is killed and retried instead of hanging first login. Antigravity's ACP server (`agy-acp-server`, ~334 MB, ~1 GB unpacked) is not part of it: `agentux-antigravity-acp.service` installs it afterwards at idle CPU and I/O priority, so the CLIs are ready first. `/etc/profile.d/agentux.sh` puts `~/.local/bin` and mise's shims on every login shell's `PATH`.
- **AgentUX:** from [agentux-core](https://github.com/agentux-os/agentux-core), the `aux` CLI and the `agentuxd` daemon, which runs as a systemd user service enabled for every user (`systemctl --global enable agentuxd.service`, socket at `$XDG_RUNTIME_DIR/agentux/agentuxd.sock`; the packaged unit's `ConditionUser=!@system` keeps it out of system users' sessions, like the first-boot wizard's); from [agentux-desktop](https://github.com/agentux-os/agentux-desktop), the AgentUX Cockpit (`agentux-cockpit`) and the Plasma 6 defaults: the AgentUX global theme, wallpaper, login screen, panel layout, Meta+A / Meta+Return shortcuts and cockpit autostart (which skips system users, so nothing opens over the first-boot wizard), with Fedora's Welcome Center no longer opened at first login, all as system-wide defaults that each user can override.
- **Welcome wizard:** after the first-boot wizard has created the account and Plasma has started, the cockpit opens **Welcome to AgentUX** once per user (not on the live ISO): agent CLI status and sign-in, a catalog of developer tools and SDKs installed per user (Flathub Flatpaks, VS Code with host integration; JetBrains IDEs through the JetBrains Toolbox App; languages and CLIs with mise; anything else in a Distrobox container), and Git and SSH. It comes from agentux-desktop with its backend, `/usr/libexec/agentux-setup`, and its catalog, `/usr/share/agentux/setup/catalog.json`; the Flathub remote is added per user from the shipped repo file. Reopen it from the app menu. See the [desktop README](https://github.com/agentux-os/agentux-desktop#welcome-wizard) and [ADR 0013](https://github.com/agentux-os/agentux/blob/main/docs/adr/0013-first-run-wizard.md).
- **User environment:** `/usr/lib/environment.d/60-agentux.conf` puts `~/.local/bin` and mise's shims on the `PATH` of the systemd user manager too, so user services (`agentuxd` and the agent CLIs it starts) and apps launched from Plasma (the cockpit) find the per-user tools, not only login shells.
- **Boot splash:** the AgentUX Plymouth theme, in the initramfs and on by default (see [Boot splash](#boot-splash)).
- **Identity:** the system calls itself AgentUX (see [Identity](#identity)).
- **First-boot wizard background:** Fedora's `Default` wallpaper is AgentUX's (see [Default wallpaper](#default-wallpaper)).

## Identity

`/usr/lib/os-release` (`/etc/os-release` links to it) names the system AgentUX, as Universal Blue images do for theirs, with AgentUX's version: the first-boot wizard says "Powered by AgentUX", and the boot menu, the installers' title bars, `hostnamectl` and KDE's About this System show `AgentUX 2026.10.15` with the AgentUX logo. Fedora's release appears only where it is labelled as the base. See [ADR 0012](https://github.com/agentux-os/agentux/blob/main/docs/adr/0012-system-version-and-release-identity.md).

<details>
<summary>Every os-release field and why</summary>

| Field | Value | Why |
|---|---|---|
| `NAME`, `PRETTY_NAME`, `VERSION` | `AgentUX`, `AgentUX 2026.10.15`, `2026.10.15` | What people see: the build's date (UTC) |
| `IMAGE_ID`, `IMAGE_VERSION`, `BUILD_ID` | `agentux`, `2026.10.15.063578e`, the same | systemd's fields for image-based systems: the build's date and short commit (build.yml passes `AGENTUX_VERSION`; a local build gets the date alone). The full commit is in `/usr/share/agentux/commit` and both are the image's `org.opencontainers.image.version` and `.revision` labels |
| `VARIANT`, `VARIANT_ID` | `Plasma`, `agentux` | |
| `LOGO` | `agentux` | The brand's app icon, installed as `agentux` in `hicolor` (16–256 px and scalable) and `/usr/share/pixmaps` |
| `HOME_URL`, `DOCUMENTATION_URL`, `SUPPORT_URL`, `BUG_REPORT_URL` | `https://agentuxos.org`, the agentux README, the agentux and agentux-os issues | |
| `DEFAULT_HOSTNAME` | `agentux` | Hostname when none is set |
| `ANSI_COLOR` | Lime | systemd prints the name in it at boot |
| `ID`, `VERSION_ID`, `CPE_NAME`, `SUPPORT_END` (and `PLATFORM_ID`, which Fedora 44 does not set) | Fedora's (`fedora`, `44`, …), unchanged; the base image's os-release is kept as `/usr/share/agentux/os-release.base` and the build and tests compare against it | Tools key on these: bootc-image-builder picks its Fedora definitions by `ID`/`VERSION_ID`, dnf5 resolves `$releasever` from `VERSION_ID`, toolbox picks `fedora-toolbox:<VERSION_ID>` by `ID`, vulnerability scanners map `CPE_NAME` to Fedora's advisories. All of that is still true of this system, so they stay Fedora's (Bluefin and Aurora change `ID` and set `ID_LIKE=fedora` instead, and carry workarounds for it). Fedora sets no `ID_LIKE` |
| `REDHAT_BUGZILLA_PRODUCT*`, `REDHAT_SUPPORT_PRODUCT*` | removed | Bug reports about this image belong to AgentUX, not Fedora's Bugzilla |

`/etc/system-release` (in Fedora a link to `fedora-release`) is `AgentUX release 2026.10.15`: bootupd names the firmware's boot entry after it (the "Fedora" entry in a UEFI boot menu becomes "AgentUX"), and the live installer takes its product name from it. `/etc/fedora-release` and `/etc/redhat-release` stay Fedora's.

[`/etc/xdg/kcm-about-distrorc`](files/etc/xdg/kcm-about-distrorc) replaces Fedora's (which pointed at Fedora's logo) for KDE's About this System: the AgentUX logo, agentuxos.org, `VERSION` instead of `VERSION_ID` next to the name, and two extra lines from scripts: **Release** (below) and **Based on** (`Fedora Linux 44 (Kinoite)`). The build fails if the Fedora fields changed or the icon is missing; the smoke and boot tests check the fields again.

</details>

### Version

A release does not rebuild the image: it promotes main's already-built, tested image to `:<tag>` and `:stable` ([Release channels](#release-channels)). So the image can carry its build (the date and commit above), but not the release it later became. Which release a system runs is worked out at run time, by `agentux-version`:

```console
$ agentux-version
AgentUX 2026.10.15 (Plasma)
  Release:   v0.5.3 (stable channel)
  Image:     ghcr.io/agentux-os/agentux:stable
  Digest:    sha256:…
  Build:     2026.10.15.063578e (commit 063578e…)
  Based on:  Fedora Linux 44 (Kinoite)
```

- **Image and channel:** the booted image reference and digest, from `bootc status` (as root) or `rpm-ostree status` (as anyone). The tag is the channel: `:stable`, `:latest` (nightly), or a pin such as `:v0.5.3`.
- **Release:** a `:v*` reference names it. Otherwise the booted digest is looked up in `https://download.agentuxos.org/releases.json`, which every release regenerates from the registry's `v*` tags (each tag with its list digest, both architectures' digests and the image version, signed like `latest.json`). `agentux-releases.timer` fetches it two minutes after boot and daily, into `/var/cache/agentux/releases.json`; offline, the cached list stays. It is one anonymous GET of a public file; `systemctl disable --now agentux-releases.timer` turns it off. The list only names things: bootc and the image signatures decide what is installed and updated.
- `agentux-version --json` gives the same for tools (the cockpit, `aux`); KDE's About page shows the Release line through `/usr/libexec/agentux/about-release`.

## Default wallpaper

<details>
<summary>Why the first-boot wizard needs its own <code>Default</code> wallpaper</summary>

plasma-setup's first-boot wizard does not follow the AgentUX theme: a Fedora patch hard-codes its background to `/usr/share/wallpapers/Default/contents/images_dark/` (`images/` with a light theme), `5120x2880.jxl` on a landscape screen and `1440x2960.jxl` on a portrait one. In Fedora, `Default` (and `Fedora`, which points at it) is a symlink owned by `desktop-backgrounds-kde` to the current release's wallpaper package (`F44`). The image points `Default` at `/usr/share/wallpapers/AgentUX-Default/` instead, a wallpaper package with exactly those four files, rendered during the build with ImageMagick (from the base image, built with librsvg and libjxl) from [`wallpaper/wizard-{dark,light}.svg`](wallpaper): the brand's key art (`wallpaper-{dark,light}.svg` next to them, copies of `brand/art/` in [agentux](https://github.com/agentux-os/agentux/tree/main/brand)) with the penguin moved by [`wallpaper/build.py`](wallpaper/build.py) to the lower third, centred and a fifth of the screen wide, so the wizard's centred "Welcome to Plasma Desktop" and **Begin Setup** stand on plain water; the portrait one is the middle of it. So the wizard, and anything else that falls back to `Default`, shows AgentUX's art; `F44` itself is untouched and still selectable. The desktop, lock and login screens keep using the `AgentUX` package from agentux-desktop. The build fails if any of the four files is not a JPEG XL of its size or `Default` stops resolving to them, and the smoke test checks the links again.

Since the symlink belongs to `desktop-backgrounds-kde`, `rpm -V desktop-backgrounds-kde` reports `....L....  /usr/share/wallpapers/Default`; that is expected.

</details>

## AgentUX versions

The AgentUX components are installed from their GitHub releases, pinned in one place, the `ARG`s at the top of the AgentUX section of the [`Containerfile`](Containerfile). The architecture-specific `agentux-cockpit` RPM remains independent of desktop configuration. Three architecture-independent bundles provide common integration and the selected desktop's settings.

| Pin | What it selects |
|---|---|
| `AGENTUX_CORE_VERSION` | `agentux-<version>-1.fc44.<arch>.rpm` from agentux-core's `v<version>` release |
| `AGENTUX_DESKTOP_VERSION` | `agentux-cockpit-<version>-1.<arch>.rpm` plus the three bundle archives from agentux-desktop's `v<version>` release |
| `AGENTUX_COMMON_SHA256` | SHA-256 pin for `agentux-desktop-common-<version>.tar.gz` |
| `AGENTUX_PLASMA_SHA256` | SHA-256 pin for `agentux-desktop-plasma-<version>.tar.gz` |
| `AGENTUX_COSMIC_SHA256` | SHA-256 pin for `agentux-desktop-cosmic-<version>.tar.gz` |

`<arch>` is the build's `uname -m`, `x86_64` or `aarch64`; any other architecture fails the build. Each variant installs the common archive first, verifies it against its pinned SHA-256, and extracts exactly one desktop bundle: Plasma for the Plasma image, COSMIC for the COSMIC image. The archives contain only `usr/` and `etc/`; configuration is baked into the immutable image rather than layered as runtime RPMs. `just bump-agentux` (needs an authenticated `gh`) checks both architecture RPMs and all three archives plus their checksum sidecars before updating any pin, and leaves `Containerfile` unchanged if a required release asset is missing or malformed. If a release ever changes the RPM's release number or Fedora tag (`-1.fc44`), update the file name in the `Containerfile` by hand.

## Boot splash

![The boot splash in the boot test's VM (1280 × 800): the AgentUX penguin in Lime on Ink, the wordmark below it, a thin wavy progress line](docs/plymouth/boot.png)

The boot splash is the brand's swimming penguin on Ink, swimming in place: it bobs gently (3 px, every 4 s), pitching with the bob, and its flipper strokes twice a cycle; the water lines of its wake stream back past it (a brighter swell scrolls through them, left, once a second); bubbles rise from the end of its back, drift back and fade. One more water line under the wordmark, a Lime wave filling a Graphite one, is Plymouth's boot progress. Shutdown and reboot show the same screen with "Shutting down" or "Restarting" instead, and offline updates a progress line with a "don't turn off" note.

![One loop of the animation](docs/plymouth/animation.gif)

If the disk is encrypted, the passphrase prompt (LUKS, from the initramfs) takes the progress line's place, the penguin keeps swimming while it waits, and "Caps Lock is on" shows under the field when it is: systemd's prompt text above a dark rounded field with one Lime dot per typed character.

<details>
<summary>How the boot splash is built, and how to preview it</summary>

How it is built:

- The theme is [`files/usr/share/plymouth/themes/agentux/`](files/usr/share/plymouth/themes/agentux/), for Plymouth's script plugin (`plymouth-plugin-script`, which the image adds): [`agentux.script`](files/usr/share/plymouth/themes/agentux/agentux.script) and ~185 KB of PNGs. Everything is sized for 1080p and scales with the screen; each image comes at 1x and @2x, so 4K screens get sharp ones. It lays the screen out again when a display changes (the firmware framebuffer handing over to the GPU driver). The firmware's logo is not kept: the splash replaces it with the Ink screen.
- [`plymouth/build.py`](plymouth/build.py) draws the PNGs from the penguin's traced geometry (`brand/src/penguin.svg` in the agentux repository, `brand/`: the same parts, wake opacity and gradient as the brand's mark) and the brand's `wordmark-mist.svg`, with resvg: `cd plymouth && npm install && python3 build.py`. It splits the mark into the parts that move: `penguin.png` (body, belly and eye, centred on the point it pitches around), `flipper.png` (centred on its root), `water.png` (a sheet of 25 frames of the wake: the water lines and the tail of the back line, the swell moving one period left over the loop) and two bubbles; and it writes their geometry into the generated block at the top of `agentux.script`. The motion itself (periods, amplitudes, speeds) is the constants block under it. Edit the scripts, not the PNGs.
- The `Containerfile` selects the theme (`plymouth-set-default-theme agentux`) and rebuilds the kernel's initramfs, `/usr/lib/modules/$kver/initramfs.img`, which is the one bootc boots: `dracut --no-hostonly --reproducible --add ostree`, as Universal Blue images do. The build fails if the theme or the script plugin is not in it.
- Plymouth shows a splash only when the kernel command line asks for one. Kinoite's image sets no kernel arguments (installers used to add `rhgb quiet`), so [`/usr/lib/bootc/kargs.d/10-agentux-splash.toml`](files/usr/lib/bootc/kargs.d/10-agentux-splash.toml) adds `rhgb quiet`; bootc applies it on install and on the next upgrade. To see boot messages instead, press Esc during boot, or remove them with `sudo rpm-ostree kargs --delete=rhgb --delete=quiet`.

To see it without installing: `python3 plymouth/preview.py` renders the animation from the theme's images (the GIF above), and [`plymouth/preview-vm.sh`](plymouth/preview-vm.sh) builds the `Containerfile`'s splash step on the base image and boots that kernel and initramfs in QEMU (software emulation in a container, no KVM, a few minutes) twice, once plain and once with a LUKS disk and a few keys typed into the prompt, saving a screenshot every half second to `output/plymouth-preview/`. The screenshot above is a frame of the boot test (tests/boot-vm.sh), which saves the splash's frames in its artifact.

</details>

## GRUB menu

On an installed system the GRUB menu (shown for a second at every boot; any key stops the countdown) is AgentUX's too: the Ink screen with the swimming penguin under the menu, entries in Slate and the selected one in Lime, in GRUB's own Unifont.

<details>
<summary>How a bootc image themes GRUB</summary>

A bootc image cannot ship files into GRUB's reach: GRUB reads only the boot partition, and bootupd writes a static `grub.cfg` there once, at install time (`/usr/lib/bootupd/grub2-static/`), and leaves it alone on updates. That `grub.cfg` sources `$prefix/console.cfg`, "GRUB console settings provided by the user/platform", before it draws the menu, and nothing else on the system writes that file. So:

- the image carries the theme in [`/usr/share/agentux/grub/`](files/usr/share/agentux/grub/): `console.cfg` (load the font, switch to the graphical terminal, set `theme`), `theme.txt`, `background.png` (1920 × 1080, from [`grub/build.py`](grub/build.py) and the brand's mark; cropped to other screen sizes) and GRUB's `unicode.pf2`, copied in at build time;
- [`agentux-grub-theme.service`](files/usr/lib/systemd/system/agentux-grub-theme.service) runs [`/usr/libexec/agentux/grub-theme`](files/usr/libexec/agentux/grub-theme) at every boot, which copies that directory to `/boot/grub2/agentux/` and its `console.cfg` to `/boot/grub2/console.cfg` when they differ from the booted image's (so theme changes arrive with `bootc upgrade`). It never touches `grub.cfg`, the boot entries or `grubenv`, so updates and rollbacks work as before; a rollback to an older image keeps the last theme, which is harmless;
- `console.cfg` is yours as much as AgentUX's: the service writes it only when there is none or when it is still exactly what it wrote last time. Edit or delete it (and `/boot/grub2/agentux/`) to get GRUB's plain menu back, or put console settings of your own in it, and the service leaves it alone. If the graphics or a file fail to load, GRUB keeps its text menu;
- the build fails if bootupd's static config stops sourcing `console.cfg`, and the boot test checks that the service ran and the files on `/boot` match the image.

bootc mounts `/boot` read-only, so the image also turns off GRUB's boot-success flag: `grub-boot-success.timer` (a user unit that runs `grub2-set-bootflag boot_success` two minutes into a session, for `grub2-mkconfig`'s hidden-menu feature) is disabled and its service masked for all users. bootupd's static `grub.cfg` always shows the menu and never reads the flag, and writing it could only fail with "Read-only file system". The live layer disables it too.

The live ISO's menu is Titanoboa's: it generates the ISO's `grub.cfg` from the entries in `iso.yaml` with no way to add a theme or source another file, so it stays GRUB's text menu (with AgentUX's entry names).

</details>

## Build and test locally

You need Linux with Podman and [`just`](https://just.systems); `vm` also needs QEMU with KVM and OVMF.

```sh
just build        # podman build -> localhost/agentux:dev (just build cosmic for the COSMIC variant)
just iso          # installer ISO from that image -> output/bootiso/install.iso (uses sudo)
just vm           # install the ISO into a VM disk, output/vm-disk.qcow2
just vm disk      # boot the installed VM disk
just live         # live ISO from the published image -> output/live/*.iso (just live localhost/agentux:dev for your build; uses sudo)
just live-test    # boot that ISO headless and run the live test, like CI (output/live-test/)
just smoke        # real first login in a container of the image, then check every tool resolves
just lint         # shellcheck + hadolint, the same checks as CI
just bump-agentux # move the AgentUX pins to the latest releases (see above)
```

<details>
<summary>What the smoke test checks</summary>

CI runs the same smoke test (`tests/smoke.sh`) on every pull request, on amd64 and arm64: it builds the image, runs it as a container, creates a regular user, runs `first-login` for real, bounded by its unit's `TimeoutStartSec` (it fails if first-login does not finish within it, and each step's result and duration go into the job summary), and checks from a clean login shell (`bash -lc`) that `claude`, `opencode`, `agy`, `codex`, `bun`, `lazygit`, `ast-grep` and `yq` print a version, that the first-login marker exists and that the system toolchain is on `PATH`. For AgentUX it checks that `aux`, `agentuxd` and `agentux-cockpit` are installed and `aux --version` / `agentuxd --version` run, that the Plasma theme is in place and selected in `/etc/xdg/kdeglobals`, that `agentuxd`, first-login and the Antigravity ACP server's unit are enabled for all users, starts `agentuxd` as the test user with a temporary `XDG_RUNTIME_DIR` and runs `aux ps` against it, and resolves the user manager's environment with `systemd-environment-d-generator` to check that `PATH` starts with `~/.local/bin` and mise's shims. For the welcome wizard it checks that the setup catalog parses, that `agentux-setup install --dry-run` prints the expected Flatpak, mise, JetBrains Toolbox and Distrobox commands, that its autostart and menu entries are in place, that the first-run marker turns the wizard off and on, and that the user's Flathub remote can be added from the shipped repo file; it then installs Flatseal (a Flatpak) and kubectl (mise) through the script for real, warning only if the container or the network does not allow it, and prints the system's Flatpak remotes. The ACP adapters (`claude-agent-acp`, `codex-acp`) and Antigravity's ACP server (`agy-acp-server`, a ~1 GB download resolved from the [ACP registry](https://github.com/agentclientprotocol/registry)) are optional: first-login installs the adapters when it can, the smoke test then installs the ACP server the way its unit does, and it only warns if any of them is missing or the ACP server's install fails or times out.

</details>

### Boot test

<details>
<summary>What the boot test checks</summary>

The smoke test never boots anything. The [Boot test](https://github.com/agentux-os/agentux-os/actions/workflows/boot.yml) workflow does: nightly against `ghcr.io/agentux-os/agentux:latest`, on demand, and on pull requests that touch the `Containerfile`, `files/` or the boot test itself (it is not a required check: it takes about an hour and needs the network inside the VM). It runs on amd64 and, where the runner has KVM, arm64 (GitHub's arm64 runners may not expose `/dev/kvm`; without it the arm64 leg reports that it skipped, since a whole Plasma boot under emulation would take hours). It builds a qcow2 with bootc-image-builder whose config adds a `boottest` user with an SSH key and password made for that run (and `systemd.wants=sshd.service` on the kernel command line, since Kinoite does not enable sshd), boots it headless under QEMU/KVM with UEFI (OVMF), and runs [`tests/boot.sh`](tests/boot.sh) over SSH:

- `bootc status` shows the expected image booted, and `systemctl --failed` is empty, for the system and the user manager;
- the boot splash is selected (`plymouth-set-default-theme` says `agentux`), the initramfs the system booted with has it and the script plugin (`lsinitrd`), and the kernel command line has `rhgb`;
- with linger enabled, `agentux-first-login.service` completes within its `TimeoutStartSec` (its CPU time, wall clock time, memory peak and each step's result and duration go into the run summary), `agentux-antigravity-acp.service` runs after it at low priority (reported the same way, warnings only), and every agent CLI and dev tool runs as a transient user service (`systemd-run --user`), i.e. with the user manager's `PATH`;
- the welcome wizard's autostart and menu entries and its backend are installed, `agentux-setup status` answers, and its first-run marker logic works (in a scratch state directory); after the autologin reboot, its autostart unit ran for the test user (warning only);
- in the first-boot wizard's session (the system user `plasma-setup`), the cockpit's autostart unit logs that it skips system users and exits successfully, nothing failed, and neither the cockpit, `agentuxd` nor first-login runs for it;
- the login screen defaults (`/usr/lib/plasmalogin/plasmalogin.conf.d/50-agentux.conf`) and the cockpit's autostart wrapper are installed, and `/etc/xdg/kded5rc` turns off the Welcome Center's kded module;
- `aux --version` reports the pinned agentux-core version, `agentuxd.service` is active, has `~/.local/bin` on its `PATH`, and `aux ps` talks to its socket;
- a second daemon with fake agents (`aux daemon --fake-agents` on a temporary socket) takes a run through plan approval, implement, a gate check and a pull request;
- `aux validate` shows a project with `isolation: {mode: podman}` running its checks in Podman, and the fake-agents daemon takes such a project through a gate whose check runs in rootless Podman ([ADR 0009](https://github.com/agentux-os/agentux/blob/main/docs/adr/0009-container-isolation-for-checks.md)); that run only warns if it fails, with the daemon log, Podman's state and SELinux denials.

Then it ends the wizard session with a display manager drop-in without autologin and screenshots the login screen, adds an autologin drop-in (on that VM only), reboots into Plasma (Wayland), checks that `kwin_wayland`, `plasmashell` and `agentux-cockpit` run with the AgentUX look-and-feel, that the cockpit's autostart unit is active, that the Welcome Center neither runs nor was launched and its kded module is not loaded, and takes screenshots through QEMU's monitor: the first boot, the login screen and the desktop. Those desktop checks are reported but do not fail the run. QEMU also takes a screenshot every half second for the first 45 seconds of the first boot and of the reboot (`splash/boot/`, `splash/reboot/` in the artifact), and the summary says whether any of them shows the boot splash; that only warns, since what a VM's screen shows that early depends on the firmware and the driver handover. The test VM's kernel command line has `plymouth.ignore-serial-consoles`, since with a serial console Plymouth would draw only text there. Screenshots, the serial console, `journalctl` for both boots and `bootc status` are uploaded as the run's artifact, with a summary on the run page.

Locally, `just boot-test` does the same with the image from `just build` (results in `output/boot-test/`).

</details>

### Live ISO test

<details>
<summary>What the live ISO test checks</summary>

The Live ISO workflow boots the amd64 ISO it built (on pull requests that touch `live/`, the live test or the workflow, weekly, and for every release) headless in QEMU/KVM with UEFI, from the CD, with an empty disk behind it, and again in a second job with legacy BIOS (QEMU's SeaBIOS, `LIVE_TEST_FIRMWARE=bios`): first as a USB stick written with `dd` up to the live session, then the whole test below from the CD, the install on a BIOS machine (the installed disk must have a BIOS boot partition and GRUB in its MBR) and the installed disk's first boot with BIOS, and talks to the live system through the QEMU guest agent the live layer ships ([`tests/live-vm.sh`](tests/live-vm.sh), which runs [`tests/live.sh`](tests/live.sh) in the VM as root):

- it waits for the live user's autologin session, then checks the selected desktop (`kwin_wayland` + `plasmashell`, or COSMIC), `agentux-cockpit`, AgentUX look-and-feel where applicable, `agentuxd` with `--fake-agents`, and `aux ps` with the demo's runs (one waiting for approval); it also checks that neither first-login nor the Antigravity ACP server unit is enabled or ran. The installer launchers, panel pin and Anaconda payload are checked too; a launcher that does not open Anaconda only warns;
- screenshots: the desktop after login and a minute later, the demo after the test approves its waiting run, and the installer opened through **Install AgentUX**; plus a screendump every 2 seconds of the first two minutes (GRUB and the boot splash, `boot/` in the artifact);
- then it installs from the live system to the VM's disk with Anaconda and the live installer's own payload (`install.ks`: the registry pull through the signature policy and the `bootc switch`). Anaconda's live mode takes no kickstart (its interactive defaults only preset values; the disk is always picked in the UI), so the test runs it as a plain kickstart install from the live session, with the answers the UI would get. Anaconda halts the live system at the end, so the test then attaches the VM's disk to the host (`qemu-nbd`) and checks the installed deployment there: it tracks the ISO's channel from the registry (`ghcr.io/agentux-os/agentux:latest`, or `:stable` for a release; `ostree-unverified-registry:`, as after a bootc-image-builder install), has the signature policy and the image's own user units, and no live user, live demo or fake-agents override. Then it boots the disk alone and screenshots its first boot. The install depends on the VM reaching ghcr.io, so a failed install only warns; an installed system that differs from a normal install fails the job. The VM gets 12 GB of RAM for it, since the live system runs in RAM.

`just live-test` does the same locally (`LIVE_TEST_INSTALL=0` skips the install).

</details>

### Installer ISO test

<details>
<summary>What the installer ISO test checks</summary>

The Build ISO workflow installs the x86_64 installer ISO it built before anything can publish it (pull requests that touch the ISO's definition or this test, the weekly build, and every release), with [`tests/iso-vm.sh`](tests/iso-vm.sh):

- it reads the ISO's own boot entry (`EFI/BOOT/grub.cfg`) and kickstart (`inst.ks=`, with what it `%include`s) and checks the kickstart installs the embedded image (`ostreecontainer`) and switches the installed system to the channel the ISO was built for (`ghcr.io/agentux-os/agentux:latest`, or `:stable` for a release);
- it makes that kickstart unattended: the ISO's lines stay as they are, minus the UI mode, plus the answers the installer's UI would get (language, time zone, the whole disk), a `boottest` user with a throwaway SSH key and password, sshd enabled, and `poweroff`;
- it boots the ISO's kernel and initrd under QEMU/KVM with UEFI and the ISO's own command line, with `inst.ks=` pointed at that kickstart on a small second CD (GRUB's menu is interactive, so it is the only part bypassed; stage 2 and the payload come from the ISO), and waits for the install to power the VM off;
- it checks the AgentUX branding: the volume label, the boot menu's names (no Fedora, no "44") and the `images/product.img` (`.buildstamp` with `Product=AgentUX`, the stylesheet, the art), then boots the ISO the way a person does (UEFI firmware, the ISO's GRUB, its default entry) and screendumps the boot menu and the graphical installer once it is drawn (`look/01-boot-menu.png`, `look/02-installer.png` in the test artifact); [`tests/installer-look.py`](tests/installer-look.py) fails the test if Anaconda wears Fedora's blue (or Anaconda's default) instead of AgentUX's Ink panels and Lime mark; the same boot with legacy BIOS (SeaBIOS, no OVMF) must reach the installer as well (`look-bios/`), since `installer/brand-iso.sh` rewrites the ISO and must keep bootc-image-builder's BIOS boot image and hybrid MBR;
- then it boots the installed disk alone and runs [`tests/boot.sh`](tests/boot.sh)'s `installed` checks over SSH ([`tests/boot-vm.sh`](tests/boot-vm.sh) with `BOOT_TEST_PHASE=installed`): `bootc` booted the channel's image from the registry, the signature policy requires the AgentUX key for all three image repositories (key and `registries.d` in place), `/etc/fstab` has no entry for `/`, the system reached `running` with no failed units, and the display manager runs.

This test found that Anaconda installs (installer and live ISO alike) started degraded: Anaconda writes the btrfs root with its mount options into `/etc/fstab`, and `systemd-remount-fs` cannot apply them to the composefs root (`overlay: No changes allowed in reconfigure`). bootc's own installer writes no root entry, so both kickstarts (`disk_config/iso.toml` and `live/install.ks`) comment it out in `%post`, and the live test checks the installed `fstab` too.

A failure fails the ISO job, so neither the weekly `publish` job nor a release publishes the ISO. The aarch64 installer ISO is built but not booted (no KVM on GitHub's arm64 runners), which the release notes and `latest.json` (`boot_tested`) say. Locally: `tests/iso-vm.sh agentux-<version>-x86_64.iso ghcr.io/agentux-os/agentux:latest output/iso-test` (needs QEMU with KVM, OVMF and xorriso).

</details>

`just qcow2 path/to/config.toml` builds a ready-to-boot disk instead (`just vm qcow2` boots it); the config should add a user with `[[customizations.user]]`. Set `AGENTUX_IMAGE` to build from another image, e.g. `AGENTUX_IMAGE=ghcr.io/agentux-os/agentux:latest just iso` after a `podman pull`.

## License

[Apache 2.0](LICENSE)
