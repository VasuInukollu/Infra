# Shared platform architecture

## Goal

Offer small projects reliable common capabilities without making every project
operate its own mail server, list manager, monitoring stack, or other commodity
service.

## Service boundary

The platform owns deployment, upgrades, backups, credentials, monitoring,
quotas, and incident response. Each consuming project owns its content, lawful
basis for contacting users, retention requirements, and application-side retry
behaviour.

Sharing is appropriate when all of the following hold:

- projects have the same operator and compatible compliance requirements;
- data can be access-controlled at the application level;
- one project's load and failure can be limited;
- restore, export, and deletion can be performed per project;
- the operational savings exceed the larger blast radius.

Use a dedicated instance or provider account when a project has a distinct
owner, regulatory boundary, high volume, untrusted administrators, contractual
isolation requirement, or materially different availability target.

## Email capability

```text
                         ┌──────────────────────────────┐
application ────────────>│ managed delivery gateway     │──> recipient
  │                      │ per-project identity/limits  │
  │                      └──────────────┬───────────────┘
  │                                     │ delivery events
  │ campaigns/templates                 v
  └──────────────────────> Listmonk ─── webhook / suppression handling
                              │
                           PostgreSQL
```

### Delivery gateway

Use a managed sender such as Amazon SES, Postmark, Mailgun, or an equivalent
regional provider. Provider selection is intentionally deferred until hosting
region, volume, budget, and compliance needs are known.

The gateway contract for every project is:

- a verified project domain or subdomain;
- a credential restricted to that identity and least-privilege send actions;
- separate transactional and bulk/marketing traffic classes;
- per-project metrics for sends, rejects, deliveries, bounces, and complaints;
- a rate limit, daily limit, alert threshold, and independent disable switch;
- bounce/complaint events connected to suppression handling.

Do not expose an unauthenticated relay. Do not run outbound mail delivery from a
generic VM for the first version; deliverability is an operational product of
its own.

### List management

Listmonk is the initial choice because it provides lists, campaigns, templates,
subscriber management, a transactional API, provider bounce webhooks, OIDC, and
list-scoped user/API permissions.

Isolation model:

- Prefix objects with the project slug: `<project>/<purpose>`.
- Give humans and API users a list role containing only their project's lists.
- Reserve global list, settings, role, user, maintenance, and SQL-query
  permissions for platform administrators.
- Treat the Listmonk database and global suppression/bounce administration as
  platform-sensitive data.

List-scoped permissions reduce accidental access, but a shared database remains
a shared security and availability boundary. Projects requiring strong tenant
isolation receive a separate instance.

### Transactional versus campaign messages

Applications should use the delivery provider API/SMTP submission directly for
password resets, receipts, alerts, and other latency-sensitive transactional
mail. Campaigns and opt-in subscriber lists go through Listmonk. The Listmonk
transactional endpoint is appropriate when a project deliberately wants shared
Listmonk templates or subscriber records; it should not become an unnecessary
hop for all application mail.

## Platform layers

| Layer | Shared responsibility | Isolation unit |
|---|---|---|
| Edge | DNS, TLS, reverse proxy, rate limiting | hostname/project |
| Identity | operator SSO, service credentials | user/project |
| Email delivery | provider integration and events | identity + traffic class |
| List management | Listmonk and PostgreSQL | list role/API user |
| Secrets | storage, rotation, access audit | secret/project/environment |
| Observability | logs, metrics, dashboards, alerts | service + project label |
| Data protection | encrypted backups and restore tests | service/database |

## Shared PostgreSQL host

The native PostgreSQL service on NUC is a shared database server for projects
that fit the platform's trust and availability boundary. Prefer reusing it over
running duplicate PostgreSQL containers. Every project or service still gets
its own database, non-superuser role, credential, backup policy, and restore
procedure. Do not share schemas, application tables, owner roles, or passwords
between projects merely because they use the same PostgreSQL server.

## Shared MariaDB host

The native MariaDB service on NUC is the shared option for projects requiring
MySQL/MariaDB compatibility. It follows the same isolation model as PostgreSQL:
one database and least-privilege user per project/service, separate credentials
and backups, and no cross-project schema or password sharing. Prefer PostgreSQL
when a project has no database-engine requirement; use MariaDB when compatibility
or application support calls for it.

## Environments

Production data must not be copied into development. Use at least `production`
and `nonproduction`, with separate credentials, sender identities, databases,
and hostnames. A local Compose deployment is for development only unless its
production operations (TLS, backups, upgrades, monitoring, secret injection,
and host hardening) are explicitly supplied.

## Initial hosting target: NUC

Production shared services will initially run on the existing NUC and be
administered through Tailscale. The host already carries unrelated applications,
which creates two important boundaries:

- Tailscale is the management path; it does not automatically determine whether
  an application is private or publicly reachable.
- Existing proxy configuration, DNS names, published ports, container networks,
  and persistent data are production dependencies and must not be replaced as a
  side effect of adding this platform.

Prefer a dedicated Compose project (or the equivalent for the NUC's confirmed
runtime), an internal application network, uniquely named volumes, and no direct
host port for Listmonk or PostgreSQL. The existing Caddy installation is the only
component that should publish the intended Listmonk hostname. PostgreSQL must
remain internal. Caddy should reach Listmonk through a deliberately shared proxy
network where the current container topology supports it; the platform must not
silently attach Caddy to Listmonk's database network.

Changes to hostnames or URLs require explicit migration planning: inventory the
current route, add and validate the new route, update clients and callbacks,
observe traffic, and only then remove the old route. When practical, retain an
HTTP redirect or temporary compatibility route. Provider webhook URLs, OAuth
callbacks, unsubscribe links, TLS certificates, DNS, and application base URLs
must be checked as part of the migration.

## Availability and recovery baseline

- Health checks cover both HTTP readiness and a synthetic provider send.
- Alert on elevated rejects, hard bounces, complaints, queue age, database
  storage, backup failure, certificate expiry, and provider quota consumption.
- PostgreSQL receives encrypted scheduled backups with a documented retention.
- Perform and record a restore rehearsal at least quarterly.
- Pin deployable versions and review release notes before upgrading.
- Document rollback and provider-disable procedures.

## Candidate future shared services

Add capabilities only when at least two projects need them and ownership is
clear. Reasonable candidates are object storage, error tracking, uptime checks,
central logs/metrics, feature flags, identity/SSO, webhook delivery, and secrets.
Avoid a shared primary application database, shared application cache, or a
single unrestricted service credential: those create coupling rather than a
platform.

## Delivery phases

1. **Foundation:** inventory the NUC, its runtime, and existing Caddy
   configuration; choose provider/secret store; establish DNS, TLS, backups,
   monitoring, and production/nonproduction separation.
2. **Email:** provision per-project identities; deploy Listmonk/PostgreSQL;
   connect delivery events; onboard one low-risk project.
3. **Hardening:** SSO, credential rotation, restore rehearsal, rate-limit and
   abuse tests, dashboards, runbooks, and upgrade automation.
4. **Expansion:** add a service only from demonstrated cross-project demand.
