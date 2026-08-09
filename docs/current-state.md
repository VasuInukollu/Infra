# Current production state

Last verified: 2026-08-09 (Asia/Kolkata)

This document contains operational metadata only. It intentionally contains no
secret values.

## Host

- Name/SSH target: `nuc`
- Management path: Tailscale
- SSH password and keyboard-interactive authentication: disabled
- SSH hardening drop-in: `/etc/ssh/sshd_config.d/00-disable-password-auth.conf`
- SSH public-key authentication: enabled and verified after reload
- Root SSH access remains permitted with public keys; password-only access was
  explicitly tested and rejected.
- OS: Ubuntu 24.04.4 LTS, x86_64
- Capacity at discovery: 4 CPU, 15 GiB RAM, 218 GiB root disk
- Docker: Snap installation, Docker 29.6.1, Compose 5.3.1
- Docker data root: `/var/snap/docker/common/var-lib-docker`
- Caddy: native systemd service, version 2.6.2 at discovery
- Active Caddyfile: `/etc/caddy/Caddyfile`
- Site imports: `/etc/caddy/sites/*.caddy`
- PostgreSQL: native PostgreSQL 16.14, listening on `127.0.0.1:5432`
- MariaDB: native MariaDB 10.11.14, listening on `127.0.0.1:3306`

The NUC hosts other applications. Notable existing dependencies include the
PrivateNumber application and `app.privatenumber.in`; verify that route after
every Caddy change.

## Shared PostgreSQL service

- The native PostgreSQL 16 server on NUC is shared infrastructure available to
  current and future projects.
- Reuse this PostgreSQL server by default instead of deploying one PostgreSQL
  container or server per project.
- Isolation is per project/service: create a dedicated database and a dedicated
  non-superuser login with access only to that database.
- Store each database credential backup under that service's root-only
  `/etc/inukollu/<service>/` directory.
- Sharing the server does not mean sharing application tables or database
  credentials between projects.

## Shared MariaDB service

- The native MariaDB 10.11 server on NUC is shared infrastructure for projects
  that require MySQL/MariaDB compatibility.
- It is active and restricted to host loopback at `127.0.0.1:3306`.
- Reuse it by default for compatible projects instead of deploying a separate
  MariaDB container or server.
- Give every project/service a dedicated database and least-privilege user.
- Store each credential backup under the service's root-only
  `/etc/inukollu/<service>/` directory; do not share schemas, users, or
  passwords between projects.

## Listmonk

- Status: deployed and publicly reachable
- URL: `https://lists.inukollu.in`
- Application root URL: `https://lists.inukollu.in`
- Version/image: `listmonk/listmonk:v6.2.0`
- Container: `listmonk`
- Restart policy: `unless-stopped`
- Network mode: host
- Application listener: `127.0.0.1:9000`
- Compose file: `/var/snap/docker/common/listmonk/compose.yaml`
- Runtime environment: `/var/snap/docker/common/listmonk/listmonk.env` (`0600`)
- Caddy site: `/etc/caddy/sites/listmonk.caddy`
- Caddy access log: `/var/log/caddy/listmonk.access.log`
- The public subscription endpoint `/api/public/subscription` returns
  `Access-Control-Allow-Origin: *` so static sites can use Listmonk's public
  double-opt-in flow. This does not apply to Listmonk's administrative API.
- Database: `listmonk` on the existing host PostgreSQL
- Database owner/login: `listmonk` (non-superuser)
- Database password backup: `/etc/inukollu/listmonk/db-password` (`0600`)
- Media provider: filesystem
- Media path in Listmonk: `uploads`, resolving to `/listmonk/uploads`
- Persistent media volume: `listmonk-uploads`
- Host volume data path:
  `/var/snap/docker/common/var-lib-docker/volumes/listmonk-uploads/_data`

Listmonk uses Docker host networking specifically because the existing
PostgreSQL server listens only on host loopback. The Listmonk HTTP listener is
also restricted to loopback and is exposed publicly only through Caddy.

## Authentication

- Initial Listmonk administrator username: `admin`
- Microsoft Entra OIDC SSO is enabled with the tenant-only application
  `listmonk-sso` (`3ca35f03-1df6-4d1f-908d-5c2ff02ccc2b`).
- OIDC callback: `https://lists.inukollu.in/auth/oidc`
- Existing admin email is mapped to `vasu@inukollu.in` for SSO matching.
- Interactive Microsoft sign-in was successfully verified on 2026-08-09.
- Automatic OIDC user creation is disabled.
- OIDC client secret backup:
  `/etc/inukollu/listmonk/oidc-client-secret` (`0600`)
- The administrator password is held by the operator; it is not stored in this
  repository.
- The temporary `/root/listmonk-initial-admin.txt` handoff file was removed
  after the operator saved the credential.
- Local admin authentication remains enabled as emergency access.
- Create scoped API users/tokens in **Admin → Users**. Do not share the admin
  credential with applications.

## API documentation

- Official Swagger UI: `https://listmonk.app/docs/swagger/`
- Official API guide: `https://listmonk.app/docs/apis/apis/`
- Instance API base: `https://lists.inukollu.in/api/`
- Swagger UI is not hosted by the Listmonk instance itself.

## DNS and TLS

At deployment, `lists.inukollu.in` resolved through:

```text
lists.inukollu.in
  -> home.inukollu.com
  -> inukollu.ddns.net
  -> 183.83.216.181
```

Caddy obtained the public certificate through an HTTP-01 ACME challenge. Both
the Listmonk route and the pre-existing PrivateNumber route returned HTTP 200
after deployment.

## PrivateNumber authentication and administration

PrivateNumber production is served at `https://app.privatenumber.in` through
the shared native Caddy service:

- Subscriber portal: `/`, static releases under
  `/opt/private-number/portal/{releases,current}`.
- API and OpenIddict: `/api/*`, `/connect/*`, `/health`, and `/alive`, service
  `private-number-api` on loopback port 5080, releases under
  `/opt/private-number/api/{releases,current}`.
- Operations application: `/admin/*`, service `private-number-admin` on
  loopback port 5090, releases under
  `/opt/private-number/admin/{releases,current}`.

PrivateNumber host configuration is under `/etc/private-number`:

- `api.env`: database connection, OpenIddict certificate password, and ACS
  SMTP settings; `root:private-number`, mode `0640`.
- `admin.env`: Entra tenant, application, and `PrivateNumber Admins` group
  object IDs; `root:private-number`, mode `0640`.
- `openiddict.pfx`: persistent signing/encryption certificate;
  `root:private-number`, mode `0640`.
- `secrets/openiddict-password`: certificate-password backup; `root:root`, mode
  `0600`.
- `secrets/postgres-password`: PostgreSQL-password backup; `root:root`, mode
  `0600`.

The admin app has no local credentials. Its single-tenant Entra application is
named `PrivateNumber Admin`; the assigned security group is
`PrivateNumber Admins`. Explicit enterprise-application assignment is
required, and only assigned-group claims are emitted.

Root-owned deployment helpers live at
`/usr/local/sbin/private-number-*-deploy`. GitHub's deployment account may call
only the helpers listed in `/etc/sudoers.d/private-number-deploy`. Application
CD activates atomic releases and cannot rewrite systemd, sudoers, Caddy, or
secret files. Repository rebuild/repair instructions live in the PrivateNumber
repository's `ops/linux/README.md` and `docs/admin-application.md`.

As of 2026-08-09, the authentication certificate/environment, admin
environment, admin unit/deployer, and additive Caddy routes are provisioned.
The first authentication/admin application release remains to be deployed.

## Outstanding operations

- Azure Communication Services Email has been selected. Its base resources are
  deployed, and `inukollu.in` and `privatenumber.in` are fully DNS-verified and
  linked. The `newsletter@privatenumber.in` sender exists with display name
  `PrivateNumber`; creation of an Inukollu sender is intentionally on hold.
  Listmonk is configured for ACS SMTP and authentication has been verified.
  Azure accepted a controlled message to `vasu@inukollu.com`; inbox placement
  remains to be confirmed. See `services/email/README.md`.
- Postal was evaluated and explicitly rejected; see ADR 0002. Do not deploy it
  unless this decision is deliberately revisited.
- Configure bounce/complaint processing.
- Set shared Listmonk site-name and logo branding when chosen; keep campaign
  sender details project-specific.
- Create per-project lists, roles, and API users.
- Back up both the `listmonk` PostgreSQL database and the `listmonk-uploads`
  volume to storage outside the NUC; no complete off-host backup was found
  during initial discovery.
- Remove bootstrap admin values from the runtime environment after confirming
  the installed version does not require them on idempotent startup.
- Consider upgrading Caddy after reviewing compatibility and release notes; do
  not combine that with an unrelated Listmonk change.

## Quick read-only verification

```bash
ssh nuc 'docker ps --filter name=^/listmonk$'
ssh nuc 'curl -fsS -o /dev/null http://127.0.0.1:9000/'
curl -fsS -o /dev/null https://lists.inukollu.in/
```

Use `services/listmonk/install.sh` for the documented deployment flow. Review
the script and current server state before rerunning it.
