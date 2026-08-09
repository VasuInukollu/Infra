# Shared Azure email delivery

Azure Communication Services Email is the managed outbound delivery layer for
Listmonk and future shared-infrastructure consumers.

## Azure resources

- Subscription: `Visual Studio Enterprise`
- Subscription ID: `8285a30d-d066-4130-89dc-aed9c4476de5`
- Resource group: `shared-infra-rg` (`centralindia`)
- Communication Service: `inukollu-shared-communication`
- Email Communication Service: `inukollu-shared-email`
- Resource/data location: `Global` / `United States`

No access keys, SMTP secrets, or Entra client secrets belong in this repository.

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
- On hold: custom Inukollu sender

Listmonk is configured to route through Azure using the active PrivateNumber
sender. SMTP authentication was verified successfully without sending mail.
The temporary pre-Azure SMTP settings backup was intentionally deleted after
the Azure configuration was verified.

On 2026-08-09, Azure SMTP accepted a controlled test message from
`newsletter@privatenumber.in` to `vasu@inukollu.com`. Confirm inbox placement
separately; SMTP acceptance alone does not prove final delivery.

## Remaining setup

1. Add an appropriate DMARC record for each root domain after reviewing their
   existing Microsoft 365 mail flow.
2. Keep the Inukollu sender on hold until it is needed.
3. Confirm inbox placement for the controlled test message.
4. Connect delivery/bounce events and request production quota after successful
   warm-up.
