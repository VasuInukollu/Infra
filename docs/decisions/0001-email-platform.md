# ADR 0001: Managed delivery with shared Listmonk

- Status: proposed
- Date: 2026-08-09

## Context

Multiple projects need transactional email, campaigns, and subscriber lists.
Running one full mail-transfer stack per project is wasteful, while operating a
shared outbound mail server introduces IP reputation, abuse response, DNS,
queueing, bounce handling, and blocklist responsibilities.

## Decision

Use a managed email delivery provider as the outbound gateway. Give each project
its own verified identity, restricted credential, configuration/traffic class,
metrics, quotas, and kill switch.

Run a shared Listmonk installation for campaign and subscriber management, with
PostgreSQL and list-scoped roles/API users. Use separate Listmonk instances where
the shared database or administrator boundary is unacceptable.

Applications send transactional messages directly through the gateway unless
they explicitly need Listmonk-managed templates or subscribers.

## Consequences

Benefits:

- delivery reputation and remote-MTA operations are delegated;
- one list-management service and database can serve several small projects;
- project credentials and traffic can be revoked or measured independently;
- the delivery provider can be changed without replacing the list manager.

Costs and risks:

- provider cost and dependency;
- shared Listmonk/PostgreSQL outage affects all campaign users;
- platform administrators can access subscriber data across projects;
- role and list provisioning must be maintained carefully.

## Revisit when

- aggregate volume makes dedicated IPs or self-hosting economically credible;
- a project needs a distinct regulatory or organizational boundary;
- provider availability or data residency is insufficient;
- Listmonk permissions cannot express a required isolation policy.
