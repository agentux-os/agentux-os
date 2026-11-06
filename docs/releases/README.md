# Release highlights

`<tag>.md` here (e.g. `v0.5.9.md`) opens the GitHub release notes of that
tag, above the generated sections (what changed, the AgentUX components, the
downloads and the images). Write it in a PR to main: the release job reads
this directory from main, so it can land after the tag, while the release's
tests run, until the approval. Without one, the notes open with the titles
of the release's feature PRs.

Start with a `## Highlights` heading and keep it short: what a user of the
release notices, with a sentence each. Preview the whole notes with
`just release-notes <tag>`.

## The aarch64 live ISOs

GitHub's arm64 runners have no KVM, so CI builds the aarch64 ISOs but does
not boot them. Before approving a release, boot its aarch64 live ISOs on an
ARM host with `tests/aarch64-live-remote.sh`: an Apple Silicon Mac with
Homebrew's `qemu` and `bash` (HVF), or a Linux host with KVM and Docker (a
Raspberry Pi 4 with 8 GB is enough):

```sh
tests/aarch64-live-remote.sh user@arm-host run:<release run id>/agentux-plasma-live-<tag>-aarch64
tests/aarch64-live-remote.sh user@arm-host run:<release run id>/agentux-cosmic-live-<tag>-aarch64
```

The host downloads each artifact straight from GitHub, and the test goes on
there if the SSH connection drops. A local ISO file or an already published
`https://download.agentuxos.org/...` URL works too.

Paste each `summary.md` under `## aarch64 live check` in `<tag>.md`. By
default the check covers the live session only: installing from the live
system needs about 12 GB of RAM for the VM, so add `LIVE_TEST_INSTALL=1
LIVE_TEST_MEMORY=12288` only on a host with room for that. The aarch64
installer ISOs are still only built.
