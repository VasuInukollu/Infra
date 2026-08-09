# Shared Infrastructure

This repository defines reusable platform services for multiple independent
projects. A project consumes a service through a documented endpoint and its own
credentials; it does not deploy another copy unless isolation requires it.

The verified live environment is recorded in
[docs/current-state.md](docs/current-state.md). Future automation sessions should
read that file and the repository-level `AGENTS.md` before operating the NUC.

## Initial architecture

```text
project-a ─┐                         ┌─ PostgreSQL + backups
project-b ─┼─ HTTPS / SMTP submission ─ shared service layer
project-c ─┘                         └─ metrics, logs, alerts
                                         │
                           managed external delivery providers
```

The first platform capability is email:

- **Mail delivery gateway** — one provider account, but a separate sending
  identity, credentials, quotas, metrics, and kill switch for each project.
- **List management** — one Listmonk installation, with lists and API users
  scoped per project.
- **Transactional mail** — projects normally send directly through the delivery
  gateway. Listmonk's transactional API is used only when its templates or
  subscriber data are specifically useful.

The canonical production URL reserved for list management is
`https://lists.inukollu.in`. It is recorded in
`environments/production.yaml`; the route is not deployed yet.

The design and its boundaries are in [docs/architecture.md](docs/architecture.md).
The email decision is in
[docs/decisions/0001-email-platform.md](docs/decisions/0001-email-platform.md).
The decision not to deploy Postal is in
[docs/decisions/0002-do-not-deploy-postal.md](docs/decisions/0002-do-not-deploy-postal.md).

## Production host

The initial production target is the existing **NUC**, administered over its
Tailscale network. It already runs other applications, so it must be treated as
a shared production host rather than an empty server. New services must use
dedicated containers, networks, volumes, ports, and hostnames and must be added
without rewriting unrelated proxy routes or restarting unrelated workloads.

Before the first deployment, inventory the NUC using the checklist in
[docs/nuc-runbook.md](docs/nuc-runbook.md). Committing deployment files here does
not authorize applying them to the NUC; deployment is a separate, reviewed step.

## Repository layout

```text
docs/                 architecture and decision records
projects/             non-secret project registrations
services/             deployable shared services (next phase)
environments/         environment-specific composition (next phase)
```

## Onboard a project

1. Copy `projects/example.yaml` to `projects/<project>.yaml`.
2. Choose a dedicated sending subdomain, for example `mail.example.com`.
3. Provision project-specific delivery credentials and DNS records (SPF, DKIM,
   DMARC); never share a global SMTP password.
4. If the project sends campaigns, create its Listmonk lists, list role, and API
   user. Do not grant `lists:get_all`, `lists:manage_all`, or unrestricted SQL.
5. Connect bounce and complaint events, then test delivery, hard bounce,
   complaint, and unsubscribe paths before enabling production traffic.
6. Record the owner, traffic class, limits, and alerts in the project file.

## Guardrails

- Transactional and marketing traffic use separate identities/configuration.
- Every project can be disabled without affecting another project.
- Secrets live in a secret manager, never in this repository or project files.
- Public services sit behind TLS and authentication; databases are private.
- Restore tests, not merely backups, are part of operating the platform.
- A shared service is not a shared failure domain by accident: noisy-neighbour
  limits and per-project observability are required.

## Next implementation milestone

Complete a read-only inventory of the NUC and its existing Caddy setup, then
choose the DNS provider, secret store, and mail delivery provider. Add a pinned
Listmonk/PostgreSQL deployment, an isolated Caddy route, encrypted backup job,
monitoring, and provider-specific infrastructure as code only after that
inventory has been reviewed.
