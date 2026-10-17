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
