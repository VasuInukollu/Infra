# Repository guidance

This repository manages shared infrastructure hosted on the server `nuc`, which
is reachable over Tailscale with `ssh nuc` as root.

Before changing the NUC, read `docs/current-state.md` and
`docs/nuc-runbook.md`. Treat it as a shared production host: inspect first, make
additive changes, validate Caddy before graceful reload, and never restart,
remove, or reconfigure unrelated services.

Important conventions:

- Caddy is native/systemd-managed and imports `/etc/caddy/sites/*.caddy`.
- Shared infrastructure secret backups belong under
  `/etc/inukollu/<service>/`, root-owned with restrictive permissions.
- Docker is installed as a Snap. Compose/runtime files that Docker must read
  belong under `/var/snap/docker/common/<service>/`.
- Never commit or print passwords, tokens, private keys, or full environment
  files.
- PostgreSQL is shared at host loopback. Each service gets a dedicated database
  and least-privilege role; do not deploy another database without an explicit
  requirement.
- MariaDB is also shared at host loopback for projects that specifically need
  MySQL/MariaDB compatibility. Give each service a dedicated database and
  least-privilege user; do not deploy another MariaDB without an explicit
  requirement.
- Preserve the existing PrivateNumber services and the
  `app.privatenumber.in` Caddy route.

Transactional applications use the shared mail gateway at
`https://resend.inukollu.in`; read `services/mail-gateway/README.md` before
integrating a project or provisioning access. Applications receive a dedicated
gateway bearer key and must never receive the shared Azure SMTP credential.

Listmonk deployment source is in `services/listmonk/`. Use Listmonk for
campaigns and subscriber management, not as the default transactional-mail path.
