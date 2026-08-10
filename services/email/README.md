# Shared Azure email delivery

Azure Communication Services Email is the managed outbound delivery layer for
Listmonk and future shared-infrastructure consumers.

Transactional applications use the authenticated mail gateway at
`https://resend.inukollu.in`; they do not receive the shared ACS SMTP
credential. The gateway applies per-project sender policy and quotas, then
submits through the same ACS SMTP identity used by Listmonk. See
`services/mail-gateway/README.md` for its API and operating procedure.

Listmonk continues to use ACS directly for campaigns and subscriber-managed
mail. The gateway does not provide campaign, subscriber, template, bounce, or
durable-queue functionality.

## Azure resources

- Subscription: `Visual Studio Enterprise`
- Subscription ID: `8285a30d-d066-4130-89dc-aed9c4476de5`
- Resource group: `shared-infra-rg` (`centralindia`)
- Communication Service: `inukollu-shared-communication`
- Email Communication Service: `inukollu-shared-email`
- Resource/data location: `Global` / `United States`

No access keys, SMTP secrets, or Entra client secrets belong in this repository.

## Sender-management identity

The mail gateway's sender-registration API requires Azure Resource Manager
access in addition to SMTP authentication. It reuses the existing
`listmonk-shared-email-smtp` principal and its already protected Entra client
secret. The custom role assigned at the `inukollu-shared-email` resource scope
is:

```text
Role name: Mail Gateway Sender Username Manager
Role definition ID: 4b1820b4-fd7e-4a4f-a2ba-b18252ef3480
Service-principal object ID: a2eaa2d7-9e29-4cd8-8101-fd49747ba62d
```

The role contains only these management actions:

```text
Microsoft.Communication/emailServices/domains/senderUsernames/read
Microsoft.Communication/emailServices/domains/senderUsernames/write
```

The role is assigned at this exact scope:

```text
/subscriptions/8285a30d-d066-4130-89dc-aed9c4476de5/resourceGroups/shared-infra-rg/providers/Microsoft.Communication/emailServices/inukollu-shared-email
```

Store the client secret only in the protected NUC file
`/etc/inukollu/mail-gateway/azure-management-client-secret`, owned by root and
readable by the `mail-gateway` group (`0640`). It is a server-side protected
copy of the same Entra secret used for ACS SMTP; never print or transfer it.

## Shared Listmonk SMTP identity

- Entra application/service-principal display name:
  `listmonk-shared-email-smtp`
- Entra application ID: `4ba502dd-6d6d-4942-8c4e-b759295009e4`
- ACS SMTP resource: `listmonk-smtp`
- SMTP login username: `listmonk-inukollu`
- Server: `smtp.azurecomm.net:587`
- Transport/authentication: STARTTLS / LOGIN
- Secret backup on NUC: `/etc/inukollu/listmonk/smtp-password` (root `0600`)
- Username backup on NUC: `/etc/inukollu/listmonk/smtp-username` (root `0600`)

The identity is shared across linked and verified sending domains; it is not
recreated per domain. The current client secret was created on 2026-08-09 with
a two-year lifetime. Rotate it before expiry and update both the protected file
and Listmonk's SMTP setting together.

## Canonical custom domains

The root domains are required so mail can use addresses ending directly in
`@inukollu.in` and `@privatenumber.in`. Both are fully verified (Domain, SPF,
DKIM, and DKIM2) and linked to `inukollu-shared-communication`. Both already
have the Azure-required SPF record. Do not publish a second SPF record.

### `inukollu.in`

| Type | DNS name | Value | TTL |
|---|---|---|---:|
| TXT | `inukollu.in` | `ms-domain-verification=b91ac48b-e97f-4d03-8c8c-3628f9267825` | 3600 |
| CNAME | `selector1-azurecomm-prod-net._domainkey.inukollu.in` | `selector1-azurecomm-prod-net._domainkey.azurecomm.net` | 3600 |
| CNAME | `selector2-azurecomm-prod-net._domainkey.inukollu.in` | `selector2-azurecomm-prod-net._domainkey.azurecomm.net` | 3600 |

DNS provider at provisioning: Microsoft-hosted nameservers under
`bdm.microsoftonline.com`.

### `privatenumber.in`

| Type | DNS name | Value | TTL |
|---|---|---|---:|
| TXT | `privatenumber.in` | `ms-domain-verification=e9447c83-7cad-4a0c-8809-1376a83c309a` | 3600 |
| CNAME | `selector1-azurecomm-prod-net._domainkey.privatenumber.in` | `selector1-azurecomm-prod-net._domainkey.azurecomm.net` | 3600 |
| CNAME | `selector2-azurecomm-prod-net._domainkey.privatenumber.in` | `selector2-azurecomm-prod-net._domainkey.azurecomm.net` | 3600 |

DNS provider at provisioning: Porkbun.

DNS interfaces may expect names relative to the zone. For example, Porkbun may
display `selector1-azurecomm-prod-net._domainkey` rather than the full name. Do
not append the zone twice.

## Current sender state

- Active: `newsletter@privatenumber.in` (`PrivateNumber`)
- Active: `accounts@privatenumber.in` (`PrivateNumber Accounts`) for
  transactional account verification and password recovery through the shared
  mail gateway
- On hold: custom Inukollu sender

Sender registration and Azure management provisioning are deployed and active.
Authenticated internal users may choose any complete sender address and display
name under an operator-verified and linked ACS domain. Domain verification stays
an operator activity; the API does not perform per-user ownership verification.
The existing newsletter identity was registered into the durable local catalog
without changing its Azure resource; `201`, idempotent `200`, and conflicting
display-name `409` behavior were verified on 2026-08-11.

Listmonk is configured to route through Azure using the active PrivateNumber
sender. SMTP authentication was verified successfully without sending mail.
The temporary pre-Azure SMTP settings backup was intentionally deleted after
the Azure configuration was verified.

On 2026-08-09, Azure SMTP accepted a controlled test message from
`newsletter@privatenumber.in` to `vasu@inukollu.com`. Confirm inbox placement
separately; SMTP acceptance alone does not prove final delivery.

On 2026-08-11, Azure accepted a controlled message submitted through the mail
gateway. An idempotent replay returned the original gateway message ID without
a second provider submission.

## Remaining setup

1. Add an appropriate DMARC record for each root domain after reviewing their
   existing Microsoft 365 mail flow.
2. Keep the Inukollu sender on hold until it is needed.
3. Confirm inbox placement for the controlled test message.
4. Connect delivery/bounce events and request production quota after successful
   warm-up.
