# ADR 0002: Do not deploy Postal

- Status: accepted
- Date: 2026-08-09

## Context

Postal was considered as a shared SMTP gateway on the NUC. Although the NUC has
sufficient capacity, a static public IP, MariaDB, RabbitMQ, and outbound port 25,
the ISP-controlled PTR hostname does not resolve forward to the sending IP and
cannot be changed. Direct delivery would therefore fail an important sender
requirement and carry unnecessary reputation and operational risk.

Running Postal only to relay through a managed provider would add another
stateful platform and queue without a demonstrated requirement that Listmonk and
applications cannot meet directly through provider SMTP/API credentials.

## Decision

Do not deploy Postal. Listmonk and individual applications will use a managed
email delivery provider directly. Keep provider credentials isolated per project
or traffic class where supported.

Azure Communication Services Email is a candidate managed provider, not yet a
selected or deployed service.

## Consequences

- No Postal containers, databases, RabbitMQ vhosts, DNS records, or Caddy routes
  will be created.
- The platform avoids operating an outbound MTA and maintaining IP reputation.
- Provider selection, domain verification, SMTP credentials, quotas, events,
  bounce handling, and monitoring remain required.
