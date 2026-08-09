# NUC deployment runbook

The NUC is a shared production host reachable through Tailscale. This runbook is
designed to prevent a new platform service from disrupting applications already
running there.

## SSH access

Password and keyboard-interactive authentication are disabled by
`/etc/ssh/sshd_config.d/00-disable-password-auth.conf`. Public-key access over
Tailscale remains enabled, including the current root administration path.

Before changing SSH configuration, always prove a fresh key-only session works.
Run `sshd -t` before a graceful `systemctl reload ssh`, keep the existing session
open, and prove both a new key-only login and rejection of password-only login.
If console recovery is required, remove or correct the `00-` drop-in, validate
with `sshd -t`, and reload SSH.

## 1. Read-only discovery

Record the following before creating or changing anything:

- operating system, architecture, available CPU, memory, and disk;
- container/runtime software and versions;
- running containers/services, health, restart policies, and Compose project
  names;
- published ports and listening processes;
- container networks and volume names/mount locations;
- Caddy version and deployment method, configuration source, imported snippets,
  existing hostnames/routes, network attachments, and certificate management;
- DNS provider and records for existing applications;
- Tailscale node name, addresses, tags, ACL/grant policy, and whether Tailscale
  Serve or Funnel is in use;
- firewall rules and which services are public, tailnet-only, or host-only;
- backup jobs, destinations, retention, last success, and last restore test;
- current resource utilization and disk-growth trends.

Store secrets nowhere in this inventory. Redact tokens, passwords, private keys,
and sensitive environment values from command output before saving it.

## 2. Proposed allocation

Prepare a change description containing:

- proposed public or tailnet-only hostname;
- proxy route and upstream container port;
- new container, network, and volume names;
- expected CPU, memory, storage, and bandwidth;
- secret injection method;
- backup and restore procedure;
- health checks, alerts, and log location;
- exact services that the deployment may restart;
- rollback steps.

Names must be checked against the discovery inventory. PostgreSQL is never
published on a host interface. Avoid fixed host ports when the reverse proxy can
reach the application on an internal container network.

## 3. Safe URL changes

Treat a hostname or base-URL change as a migration, not a text replacement.

1. Find every consumer: proxy routes, DNS, TLS, OAuth callbacks, CORS policy,
   provider webhooks, email links/templates, monitoring, bookmarks, and project
   configuration.
2. Add the new DNS name and route without removing the old one.
3. Validate TLS, authentication, application assets, API calls, webhooks, and
   health checks through the new name.
4. Update consumers and observe both routes for a defined migration period.
5. Redirect the old hostname when safe; do not redirect signed webhook requests
   unless the provider explicitly supports it.
6. Remove the old route only after traffic and dependency checks show it is no
   longer required.

## 4. Caddy change procedure

Do not replace the existing Caddyfile or assume its filesystem location. After
discovery, add the smallest possible site block, preferably through the host's
existing import/snippet convention.

The intended route shape is conceptually:

```caddyfile
lists.example.com {
    reverse_proxy listmonk:9000
}
```

The hostname and upstream name above are placeholders, not deployable values.
Before applying a route:

1. Confirm that the hostname does not already exist in Caddy or DNS.
2. Confirm Caddy can resolve and reach the upstream on a proxy-only network.
3. Run `caddy fmt --diff` against the proposed configuration.
4. Run `caddy validate` using the same config and adapters as the running Caddy.
5. Back up the active configuration.
6. Use Caddy's graceful reload mechanism; do not restart the host or unrelated
   containers.
7. Verify the new route, TLS certificate, and all pre-existing routes.

Caddy receives access only to Listmonk's application port. It must not join the
private database network or receive database credentials.

## 5. Deployment guardrails

- Render and review configuration before applying it.
- Pin container image versions; do not deploy floating `latest` tags.
- Back up affected configuration and data before changes.
- Start only the new Compose project/services; do not issue host-wide down,
  prune, or restart commands.
- Verify existing application health before and after the change.
- Roll back if an unrelated application, route, or certificate is affected.
- Record what changed, when, by whom, and how it was verified.

## 6. Information still required

- How containers or services are currently managed on the NUC.
- How Caddy is installed and where its active configuration is sourced.
- Whether Listmonk should be public, tailnet-only, or split between a public
  subscription endpoint and tailnet-only administration.
- Desired hostname and the DNS zone available for it.
