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
ARM host with KVM and Docker (a Raspberry Pi 4 with 8 GB is enough) with
`tests/aarch64-live-remote.sh`:

```sh
gh run download <release run id> -R agentux-os/agentux-os \
    -n agentux-plasma-live-<tag>-aarch64 -D isos
tests/aarch64-live-remote.sh user@arm-host isos/agentux-plasma-live-<tag>-aarch64.iso
```

Do the same for `agentux-cosmic-live-<tag>-aarch64`. An already published
ISO can be given by its `https://download.agentuxos.org/...` URL instead.
Paste each `summary.md` under `## aarch64 live check` in `<tag>.md`. The
check covers the live session only: installing from the live system needs
about 12 GB of RAM, and the aarch64 installer ISOs are still only built.
