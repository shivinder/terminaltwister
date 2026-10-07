# Role: tls (Step 4)

Let's Encrypt certificate + HTTPS enforcement.

## What it does

- Installs certbot with its Route53 plugin and obtains a certificate via **DNS-01** validation: certbot publishes a TXT record at `_acme-challenge.<name>` for every name on the certificate (`domain`, plus `www.` when `www_alias`), waits for Route53 to serve it, and removes it afterwards. Let's Encrypt never connects to this host
- Switches an existing certificate's renewals to Route53 if it was issued another way — one from before this role used DNS-01, or restored from an older config backup — after rehearsing a renewal against Let's Encrypt's staging service
- Re-renders the nginx vhost (via `wordpress` role's `tasks/vhost.yml`): port 80 becomes a 301 redirect to HTTPS; port 443 serves the site with TLS 1.2/1.3 and HTTP/2
- Installs a certbot deploy hook that reloads nginx after each auto-renewal (the certbot package ships a systemd renewal timer; renewals use the same Route53 validation)
- HSTS is added by the `wp_hardening` role's security-headers snippet

## Prerequisites

- **The instance role must be allowed to write the challenge records.** Terraform grants this per name through `certificate_names` in `infra/envs/<env>/main.tf`, which has to list the same names as above; `terraform output certificate_names` shows what was granted. A name missing there fails certbot with an `AccessDenied` on `route53:ChangeResourceRecordSets`. The grant is limited to those `_acme-challenge` TXT records, so an instance cannot edit anything else in the zone or obtain a certificate for the other environment's name.
- The names must live in a Route53 hosted zone in this AWS account.
- **The A record does not need to point here**, and port 80 does not need to be reachable, so the certificate can be issued before a DNS cutover. The play's closing smoke test and the CI deploy job still need the name to resolve to this instance.
- The [`wp_install`](../wp_install) role runs immediately after this one, so `wp core install` records an `https` URL only once issuance has actually succeeded.

## Backup and recovery

`/etc/letsencrypt` — the account key, the certs and their private keys — is
included in the `ops` role's nightly `config_*.tar.gz`. Certbot would happily
re-issue on a rebuilt instance, but Let's Encrypt rate-limits duplicate
certificates (5 per week for an identical hostname set), which is easy to burn
through while iterating on a rebuild. Restoring the directory sidesteps that:
`cp -a letsencrypt /etc/` then reload nginx. Details in `roles/ops/README.md`.

Nothing here is `enable_tls: false`-safe by accident: with TLS off the directory
does not exist, and the backup script skips it rather than failing.

## Key variables

| Variable | Purpose |
|---|---|
| `enable_tls` | Set `false` to skip this role (e.g., TLS terminated at an ALB/CloudFront) |
| `domain`, `admin_email` | Certificate subject and expiry contact |
| `www_alias` | Adds `www.{{ domain }}` to the cert; nginx 301-redirects www to the apex |

Run alone: `ansible-playbook site.yml --tags tls`
