# Role: tls (Step 4)

Let's Encrypt certificate + HTTPS enforcement.

## What it does

- Installs certbot and obtains a certificate via **webroot** validation (the HTTP vhost from the `wordpress` role serves the ACME challenge)
- Re-renders the nginx vhost (via `wordpress` role's `tasks/vhost.yml`): port 80 becomes a 301 redirect to HTTPS; port 443 serves the site with TLS 1.2/1.3 and HTTP/2
- Installs a certbot deploy hook that reloads nginx after each auto-renewal (the certbot package ships a systemd renewal timer)
- HSTS is added by the `wp_hardening` role's security-headers snippet

## Prerequisites

- **DNS A record for `domain` must already point to this instance** (Elastic IP recommended), and port 80 must be reachable — otherwise issuance fails.

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
