# Role: wp_hardening (Step 6)

WordPress- and nginx-level hardening for a public-facing site.

## What it does

- `server_tokens off` (hide nginx version)
- Populates the snippets the vhost already includes:
  - **security-headers.conf** — X-Frame-Options, nosniff, Referrer-Policy, Permissions-Policy, HSTS (when TLS)
  - **wp-security.conf** — deny `xmlrpc.php`, dotfiles (except `.well-known`), `wp-config.php`, PHP in uploads, readme/license
  - **wp-login-limit.conf** — `limit_req` on `wp-login.php` (zone: `login_rate_limit`, burst: `login_burst`, returns 429)
- fail2ban jail banning IPs that hammer `wp-login.php`
- Deletes unused default plugins/themes via WP-CLI
- (Set by `wordpress` role's wp-config: `DISALLOW_FILE_EDIT`, minor core auto-updates, 640 on wp-config)

## Key variables

| Variable | Purpose |
|---|---|
| `login_rate_limit`, `login_burst` | wp-login.php rate limiting |
| `hsts_max_age` | HSTS lifetime |

## Manual follow-ups (not automatable here)

- Enable a 2FA plugin for admin accounts
- Consider a security plugin (e.g., Wordfence) or external scanning
- Test and add a Content-Security-Policy (omitted by default — breaks many themes)

Run alone: `ansible-playbook site.yml --tags hardening`
