# Shared mail gateway

The mail gateway is the API-only transactional email submission service for
Inukollu applications. It exposes a stable, Resend-shaped contract and relays
accepted messages through Azure Communication Services (ACS) Email over
authenticated SMTP with STARTTLS. Listmonk remains separate and continues to
own campaigns and subscriber management.

Application teams should start with the
[consumer quickstart](../../docs/mail-gateway-quickstart.md). This document is
the full API and operator reference.

## Production service

- Public URL: `https://resend.inukollu.in`
- Send endpoint: `POST /v1/emails`
- Register sender: `POST /v1/senders`
- List senders: `GET /v1/senders`
- Health: `GET /health`
- Readiness: `GET /ready`
- NUC listener: `127.0.0.1:5085`
- systemd service: `mail-gateway`
- Application: `/opt/mail-gateway/{releases,current}`
- Configuration: `/etc/inukollu/mail-gateway/appsettings.Production.json`
- Caddy site: `/etc/caddy/sites/mail-gateway.caddy`
- Source: `https://github.com/inukollu/Resend`

Caddy is the public TLS boundary. Email submission requires a project bearer
key. Health and readiness disclose no credentials or message data and do not
submit mail.

The sender endpoints and Azure management provisioning are active in production
and enforce project bearer authentication. The initial durable catalog contains
`newsletter@privatenumber.in` with display name `PrivateNumber`.

## Sender registration

Authenticated internal users choose both the complete sender email address and
display name. Domain verification and linking remain centralized operator
activities in Azure; the API does not enforce per-user domain ownership.

```http
POST /v1/senders HTTP/1.1
Host: resend.inukollu.in
Authorization: Bearer project_api_key
Content-Type: application/json

{
  "email": "billing@privatenumber.in",
  "display_name": "PrivateNumber Billing"
}
```

A new sender is registered beneath its verified ACS domain, persisted, and
returned with `201 Created`. Repeating the same normalized email and display
name returns the existing record with `200 OK`. The same email with a different
display name is not allowed to overwrite the global Azure sender resource and
returns:

```http
409 Conflict
```

```json
{
  "code": "sender_already_exists",
  "message": "This sender email is already registered with a different display name."
}
```

`GET /v1/senders` returns the global registered-sender catalog to authenticated,
enabled projects. Successfully registered senders are accepted by
`POST /v1/emails` in addition to statically configured sender allowlists. A
domain that has not yet been prepared by the operator returns
`422 domain_not_available`.

## Application request

Every submission requires both `Authorization` and `Idempotency-Key`:

```http
POST /v1/emails HTTP/1.1
Host: resend.inukollu.in
Authorization: Bearer project_api_key
Idempotency-Key: signup-123-welcome
Content-Type: application/json

{
  "from": "PrivateNumber <newsletter@privatenumber.in>",
  "to": ["user@example.com"],
  "cc": [],
  "bcc": [],
  "reply_to": "support@privatenumber.in",
  "subject": "Welcome",
  "html": "<p>Welcome!</p>",
  "text": "Welcome!",
  "headers": {},
  "tags": [
    { "name": "type", "value": "welcome" }
  ]
}
```

A successful response means Azure accepted the SMTP submission:

```json
{
  "id": "email_019fed91559b74c89ad111b96aa1f8f1"
}
```

The status is `202 Accepted`. It does not prove inbox delivery.

Supported fields are `from`, `to`, `cc`, `bcc`, `reply_to`, `subject`, `html`,
`text`, `headers`, `tags`, and inline `attachments`. The contract uses the
official Resend .NET `EmailMessage` JSON shape. Hosted templates, scheduled
sending, and remote attachment paths are rejected. At least one of `html` or
`text` is required.

### Retry and error behavior

- Reuse the same idempotency key when retrying the same logical message.
- A successful replay returns the original message ID without resubmitting.
- Reusing a key with a different payload returns `409`.
- `401` means the bearer key is missing or invalid.
- Other `4xx` responses indicate validation, sender policy, project disablement,
  recipient policy, or quota failure and should not be blindly retried.
- `5xx` indicates a temporary gateway or Azure failure. Retry with backoff and
  the same idempotency key.

Idempotency records, rate counters, and daily counters are process-local in the
current stateless version. They reset when the service restarts. Applications
must retain their own logical idempotency keys and must not treat the gateway
as a durable queue.

## Project access

Applications never receive the shared ACS SMTP credential. Each project and
environment receives an independently revocable gateway bearer key with:

- a unique project ID;
- an exact-address or domain sender allowlist;
- per-minute and daily limits;
- a kill switch;
- optional recipient-domain restrictions for nonproduction.

The initial project is `default-production` and permits the PrivateNumber
senders `newsletter@privatenumber.in` and `accounts@privatenumber.in`. The
newsletter identity is for campaigns; account verification and recovery use
the accounts identity. Its root-only handoff is on the NUC at:

```text
/etc/inukollu/mail-gateway/project-keys/default-production
```

Do not copy keys into this repository, other infrastructure documentation, or
chat. Store a project key in that application's secret manager or protected
runtime configuration.

### Provision a project key

Perform this as root on the NUC. Replace the placeholders before running it:

```bash
project_id=example-production
key_file="/etc/inukollu/mail-gateway/project-keys/${project_id}"
umask 077
openssl rand -hex 32 > "$key_file"
api_key_hash="$(tr -d '\r\n' < "$key_file" | sha256sum | awk '{print $1}')"
```

Add a project object to `MailGateway.Projects` in
`/etc/inukollu/mail-gateway/appsettings.Production.json`. Store only
`api_key_hash`, never the raw key:

```json
{
  "Id": "example-production",
  "Environment": "production",
  "ApiKeySha256": "SHA256_HEX_HERE",
  "Enabled": true,
  "RatePerMinute": 60,
  "DailyLimit": 1000,
  "AllowedSenders": ["notifications@example.in"],
  "AllowedRecipientDomains": []
}
```

Use `*@example.in` only when every address under that domain is intentionally
authorized. For nonproduction, populate `AllowedRecipientDomains` so a test
system cannot email arbitrary recipients.

Validate the JSON, restart only `mail-gateway`, and check readiness:

```bash
jq empty /etc/inukollu/mail-gateway/appsettings.Production.json
systemctl restart mail-gateway
systemctl is-active mail-gateway
curl -fsS http://127.0.0.1:5085/health
curl -fsS http://127.0.0.1:5085/ready
```

Give the raw key to the application owner through a secure channel. Retain the
root-only handoff for controlled recovery. To revoke access immediately, set
`Enabled` to `false` and restart the service; rotate by issuing a new raw key
and replacing its stored digest.

## Provider credentials and logs

The gateway reads the shared ACS username and password from:

```text
/etc/inukollu/mail-gateway/smtp-username
/etc/inukollu/mail-gateway/smtp-password
```

They are `root:mail-gateway` mode `0640`. The canonical root-only Listmonk
backups remain under `/etc/inukollu/listmonk/`. Rotate the protected copies
together when the shared Entra client secret changes.

Sender registration uses this Azure Resource Manager credential path:

```text
/etc/inukollu/mail-gateway/azure-management-client-secret
```

It is `root:mail-gateway` mode `0640` and is a protected server-side copy of the
existing ACS principal's Entra client secret. The active `AzureManagement`
configuration references tenant `1b7d2958-9eba-424d-ba9f-3104f2fd85ac`, client
`4ba502dd-6d6d-4942-8c4e-b759295009e4`, subscription
`8285a30d-d066-4130-89dc-aed9c4476de5`, resource group `shared-infra-rg`, and
Email Communication Service `inukollu-shared-email`.

The custom role `Mail Gateway Sender Username Manager` (definition
`4b1820b4-fd7e-4a4f-a2ba-b18252ef3480`) is assigned to service-principal object
`a2eaa2d7-9e29-4cd8-8101-fd49747ba62d` at the Email Communication Service
scope. It contains only:

```text
Microsoft.Communication/emailServices/domains/senderUsernames/read
Microsoft.Communication/emailServices/domains/senderUsernames/write
```

Successful sender records persist independently of immutable application
releases at:

```text
/var/lib/mail-gateway/senders.json
```

The directory is `mail-gateway:mail-gateway` mode `0750`; the registry file is
mode `0640`. The hardened systemd unit uses `UMask=0027` and grants
`ReadWritePaths=/var/lib/mail-gateway`. Deployment preserves the registry across
releases and rollbacks.

### Sender registration verification

On 2026-08-11, `newsletter@privatenumber.in` with its existing display name
`PrivateNumber` was used to verify the complete path without changing Azure:

- first local registration returned `201`;
- identical replay returned `200` with the same sender ID;
- a different display name returned `409 sender_already_exists`;
- the catalog survived service restart and CD deployment;
- unauthenticated `GET /v1/senders` returned `401`;
- public gateway health/readiness, Listmonk, and PrivateNumber remained healthy.

The active release after this work was `/opt/mail-gateway/releases/31440048131-1`.
Detailed implementation and rollback guidance also lives in the Resend source
repository at `docs/sender-registration.md`.

Logs contain message ID, project, environment, sender domain, and recipient
domains. They must never contain message bodies, attachments, bearer keys, or
SMTP credentials:

```bash
journalctl -u mail-gateway -n 100 --no-pager
```

## Deployment and rollback

CI and CD live in the Resend repository as `ci.yaml` and `cd.yaml`. Successful
CI on `main` produces the Linux x64 artifact. CD joins Tailscale as `tag:ci`,
uses the restricted `privatenumber-deploy` SSH account, and invokes only:

```text
sudo /usr/local/sbin/mail-gateway-deploy
```

The root-owned helper creates an immutable release, changes the `current`
symlink, restarts only `mail-gateway`, verifies health and readiness, and rolls
back automatically on failure. GitHub cannot change Caddy, systemd, or service
secrets. Do not deploy manually unless repairing CD or performing a documented
recovery.

## Read-only verification

```bash
ssh nuc 'systemctl is-active mail-gateway'
ssh nuc 'ss -ltn | grep 127.0.0.1:5085'
curl -fsS https://resend.inukollu.in/health
curl -fsS https://resend.inukollu.in/ready
```
