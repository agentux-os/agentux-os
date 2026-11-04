# AgentUX RPM signing key

`RPM-GPG-KEY-agentux` goes here: the public half of the key agentux-core and
agentux-desktop sign their RPMs with (agentux-core `docs/releasing.md`).

With the file present, the image build checks every AgentUX RPM's signature
against it and fails on a missing or wrong one, and installed systems get it
in `/etc/pki/rpm-gpg/`. Without it the build warns and installs them
unchecked (the RPMs are fetched over HTTPS from the projects' GitHub
releases, pinned by version).

Commit the key here only after the releases the image pins are signed with
it.

Current key: `AgentUX RPM Signing Key`, RSA 4096, fingerprint
`7217 759E 0D14 1913 9B7C  148C 3116 C5F0 DECE 4517`, expires 2029-11-03.
The first releases signed with it are agentux-core 0.5.1 and
agentux-desktop 0.5.13.
