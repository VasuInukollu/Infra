# Mail gateway quickstart

Use the shared mail gateway for transactional application messages such as
password resets, receipts, verification links, and alerts. Use Listmonk for
campaigns, subscriber lists, and unsubscribe workflows.

## Production endpoint

```text
POST https://resend.inukollu.in/v1/emails
```

Each project and environment receives its own bearer key, sender allowlist,
rate limit, daily limit, and kill switch. Applications must not receive or use
the shared Azure Communication Services SMTP credential.

## Request access

1. Register the non-secret settings in `projects/<project>.yaml`, using
   `projects/example.yaml` as the template.
2. Specify the environment, exact sender addresses or deliberately authorized
   sender domain, per-minute and daily limits, and nonproduction recipient
   restrictions.
3. Ask the shared-infrastructure operator to provision the gateway project and
   bearer key using `services/mail-gateway/README.md`.
4. Transfer the raw key through a secure channel and store it only in the
   application's protected runtime configuration. Do not commit it or include
   it in logs, documentation, issues, or chat.

Use a separate project ID and bearer key for every environment. Nonproduction
projects should restrict recipient domains so test systems cannot email the
public accidentally.

## Sender registration

`POST /v1/senders` and `GET /v1/senders` are active and enforce project bearer
authentication. The operator verifies and links domains in Azure. Authenticated
projects may then register a complete sender email and display name under an
operator-prepared domain and list the global sender catalog.

Registering a new identity returns `201`. Registering the same normalized email
and display name is idempotent and returns `200`; attempting to use a different
display name for an existing normalized email returns
`409 sender_already_exists`. A domain that is not prepared in Azure returns
`422 domain_not_available`.

```bash
curl --fail-with-body \
  https://resend.inukollu.in/v1/senders \
  -H "Authorization: Bearer $MAIL_GATEWAY_API_KEY" \
  -H 'Content-Type: application/json' \
  --data '{
    "email": "notifications@mail.example.com",
    "display_name": "Example Notifications"
  }'
```

## Send a message

Every request requires a bearer key and an `Idempotency-Key`:

```bash
curl --fail-with-body \
  https://resend.inukollu.in/v1/emails \
  -H "Authorization: Bearer $MAIL_GATEWAY_API_KEY" \
  -H "Idempotency-Key: password-reset-APPLICATION_EVENT_ID" \
  -H 'Content-Type: application/json' \
  --data '{
    "from": "Example <notifications@mail.example.com>",
    "to": ["user@example.com"],
    "subject": "Reset your password",
    "html": "<p>Use the link in the application to reset your password.</p>",
    "text": "Use the link in the application to reset your password."
  }'
```

Replace `APPLICATION_EVENT_ID` with a stable identifier for the logical message,
not a new random value on every retry. Do not put secrets or sensitive reset
tokens into the idempotency key.

A successful submission returns `202 Accepted` and a gateway message ID:

```json
{"id":"email_019fed91559b74c89ad111b96aa1f8f1"}
```

This means Azure accepted the SMTP submission; it does not prove delivery to
the inbox.

## Retries and errors

- Retry `5xx` responses with exponential backoff and the same idempotency key.
- A successful replay returns the original message ID without resubmitting.
- Do not blindly retry validation, authentication, sender-policy, or quota
  failures reported as `4xx`.
- Reusing an idempotency key with a different payload returns `409`.
- The gateway is not a durable queue. The application remains responsible for
  retaining its logical event and retry state.

The full request fields, attachment rules, project provisioning procedure, and
operator commands are documented in
[`services/mail-gateway/README.md`](../services/mail-gateway/README.md).
