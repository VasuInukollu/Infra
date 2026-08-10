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

- **Transactional mail gateway** — the deployed API at
  `https://resend.inukollu.in` gives each project/environment a separate bearer
  key, sender allowlist, quotas, and kill switch while keeping the shared Azure
  credential private. See [the consumer quickstart](docs/mail-gateway-quickstart.md).
- **Sender management** — authenticated sender registration and listing are
  deployed with narrowly scoped Azure provisioning and durable registry state.
  Users choose the complete sender email and display name; domain verification
  and linking remain centralized Azure operator tasks.
- **List management** — one Listmonk installation, with lists and API users
  scoped per project.
- **Transactional mail** — projects normally send directly through the delivery
  gateway. Listmonk's transactional API is used only when its templates or
  subscriber data are specifically useful.

The platform also provides a host-local GeoIP lookup API on the NUC. It is
available only at `http://127.0.0.1:8082` and refreshes its bundled GeoLite2
database automatically each week; see `services/geoip-api/`.

The production endpoints are `https://resend.inukollu.in` for transactional
mail submission and `https://lists.inukollu.in` for list management and
campaigns. Both are deployed and recorded in `environments/production.yaml`.

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
services/             deployable shared services and operating guides
environments/         non-secret environment inventory
```

## Onboard a project

1. Copy `projects/example.yaml` to `projects/<project>.yaml`.
2. Choose the project's sending domain and requested sender addresses. A shared
   infrastructure operator must verify and link the domain in Azure.
3. Provision a mail-gateway project entry and bearer key as described in the
   [mail-gateway quickstart](docs/mail-gateway-quickstart.md). Store the raw key
   only in the application's protected configuration; never give applications
   the shared Azure SMTP credential.
4. Configure the application to call `POST https://resend.inukollu.in/v1/emails`
   with its bearer key and a stable `Idempotency-Key` for each logical message.
5. If the project sends campaigns, create its Listmonk lists, list role, and API
   user. Do not grant `lists:get_all`, `lists:manage_all`, or unrestricted SQL.
6. Connect bounce and complaint events, then test delivery, hard bounce,
   complaint, and unsubscribe paths before enabling production traffic.
7. Record the owner, gateway project ID, senders, limits, and alerts in the
   project file.

## Guardrails

- Transactional and marketing traffic use separate identities/configuration.
- Every project can be disabled without affecting another project.
- Secrets live in a secret manager, never in this repository or project files.
- Public services sit behind TLS and authentication; databases are private.
- Restore tests, not merely backups, are part of operating the platform.
- A shared service is not a shared failure domain by accident: noisy-neighbour
  limits and per-project observability are required.

## Current operational priorities

Complete bounce and complaint processing, add monitoring and alerts for the
mail gateway and Azure quota, establish off-host Listmonk backups with restore
tests, and onboard projects with isolated gateway keys and sender policies.
