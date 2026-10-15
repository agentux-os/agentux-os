# AgentUX OS profiles

The signed image is the same for every role. The profile manager records the
role selected during installation and applies it on first boot:

```sh
agentux profile show
agentux profile plan workstation
sudo agentux profile apply node
```

Available profiles are `workstation`, `node`, `command`, `executive`,
`complete` and `custom`. The catalog is read-only; applied state is kept in
`/var/lib/agentux/profile.json` and an installer seed is consumed from
`/var/lib/agentux/profile-intent.json`.

The `command` profile is intentionally fail-closed in this OS release. It
needs an explicit Command image and configuration before any Quadlet material
is written:

```sh
sudo AGENTUX_COMMAND_IMAGE=... \
  AGENTUX_COMMAND_CONFIG=/etc/agentux/command/config.env \
  agentux profile apply command
```

PostgreSQL, Temporal, NATS and object storage remain container services owned
by `agentux-command`; they are never installed as OS packages.
