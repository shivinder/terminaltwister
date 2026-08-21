# Role: wordpress (Step 3)

Installs WordPress, WP-CLI, and the nginx vhost.

## What it does

- Installs WP-CLI to `/usr/local/bin/wp`
- Downloads WordPress core to `wp_root` (as `www-data`)
- Generates `wp-config.php` with fresh salts from the WordPress API (**once** — never rotated on re-runs), hardened constants (`DISALLOW_FILE_EDIT`, `WP_AUTO_UPDATE_CORE minor`), and Redis defines when `enable_redis_cache`
- Permissions: dirs 755, files 644, `wp-config.php` 640, owner `www-data`
- Renders the nginx vhost (`tasks/vhost.yml`) — HTTP-only until a certificate exists, then HTTP→HTTPS redirect + TLS. Includes FastCGI page-cache directives when `enable_fastcgi_cache`
- Optional headless install (`wp_auto_install: true`): runs `wp core install` so the public web installer is never exposed

## Key variables

| Variable | Purpose |
|---|---|
| `wp_root`, `domain`, `wp_locale`, `wp_table_prefix` | Install location and identity |
| `wp_auto_install`, `wp_site_title`, `wp_admin_user`, `wp_admin_password` | Headless install |
| `enable_fastcgi_cache`, `fastcgi_cache_*` | Page cache in the vhost |

## Notes

- `tasks/vhost.yml` is re-used by the `tls` role (`include_role: tasks_from=vhost`) to re-render the vhost after the cert is issued.
- The vhost includes placeholder snippets that the `wp_hardening` role later fills in — nginx stays valid at every step.
- **The salts exist in exactly one place**, and this role will not write them a second time (`when: not wp_config.stat.exists`). Lose them and every session is invalidated, plus any plugin data encrypted with `AUTH_KEY` is gone for good — a database restore cannot bring it back. That is why the `ops` role backs `wp-config.php` up nightly. Do **not** restore that file wholesale onto a rebuilt instance, though: `wp_db_host` is the old instance's private IP. Copy only the salt block — `roles/ops/README.md`, "Rebuilding from scratch".

Run alone: `ansible-playbook site.yml --tags wordpress`
