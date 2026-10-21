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
is written. The configuration is `/var/lib/agentux/command/command.env`, the
file agentux-command's Quadlet reads; the profile creates its directory:

```sh
sudo AGENTUX_COMMAND_IMAGE=... \
  AGENTUX_COMMAND_CONFIG=/etc/agentux/command/config.env \
  agentux profile apply command
```

PostgreSQL, Temporal, NATS and object storage remain container services owned
by `agentux-command`; they are never installed as OS packages.

## Unattended machines

`agentux-provision.service` sets a machine up on first boot from a provision file (profile, Command enrollment, node policy, agent preferences), found on the kernel command line (`agentux.provision=/path`), in QEMU's fw_cfg (`opt/org.agentux/provision`), on a filesystem labelled `AGENTUX`, or in `/boot` or `/etc/agentux/provision.yaml`. See `aux provision` in agentux-core's `docs/provision.md`.
