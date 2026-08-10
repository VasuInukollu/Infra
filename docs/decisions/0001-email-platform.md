# ADR 0001: Managed delivery with shared Listmonk

- Status: accepted
- Date: 2026-08-09
- Updated: 2026-08-11

## Context

Multiple projects need transactional email, campaigns, and subscriber lists.
Running one full mail-transfer stack per project is wasteful, while operating a
shared outbound mail server introduces IP reputation, abuse response, DNS,
queueing, bounce handling, and blocklist responsibilities.

## Decision

Use Azure Communication Services Email as the managed outbound provider. Put a
small, provider-independent transactional mail gateway in front of it. Give
each project/environment its own gateway bearer key, verified sender policy,
traffic limits, metrics, and kill switch; do not distribute the shared Azure
SMTP credential to applications.

Run a shared Listmonk installation for campaign and subscriber management, with
PostgreSQL and list-scoped roles/API users. Use separate Listmonk instances where
the shared database or administrator boundary is unacceptable.

Applications send transactional messages through the shared mail gateway at
`https://resend.inukollu.in` unless they explicitly need Listmonk-managed
templates or subscribers. The gateway contract remains stable if Azure is later
replaced by Postal, SES, or another provider.

Keep domain verification and linking under platform-operator control. The
gateway may allow authenticated projects to register sender addresses only
within operator-prepared domains. Sender-management Azure permissions use a
narrowly scoped management identity and are separate from SMTP submission
credentials.

## Consequences

Benefits:

- delivery reputation and remote-MTA operations are delegated;
- one list-management service and database can serve several small projects;
- project credentials and traffic can be revoked or measured independently;
- the delivery provider can be changed without replacing the list manager.

Costs and risks:

- provider cost and dependency;
- the gateway is another shared availability boundary;
- its initial idempotency and quota state is process-local and resets on restart;
- shared Listmonk/PostgreSQL outage affects all campaign users;
- platform administrators can access subscriber data across projects;
- role and list provisioning must be maintained carefully.

## Revisit when

- aggregate volume makes dedicated IPs or self-hosting economically credible;
- a project needs a distinct regulatory or organizational boundary;
- provider availability or data residency is insufficient;
- Listmonk permissions cannot express a required isolation policy.
