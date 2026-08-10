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

The initial project is `default-production` and currently permits only
`newsletter@privatenumber.in`. Its root-only handoff is on the NUC at:

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
