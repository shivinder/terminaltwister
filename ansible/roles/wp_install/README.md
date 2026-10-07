# Role: wp_install (Step 5)

Runs `wp core install` — the headless install that keeps WordPress's public
setup wizard from ever being reachable.

## Why this is not part of the `wordpress` role

`wp core install --url=` writes the site's own address into the database, and
nothing revisits it afterwards: the [`wordpress`](../wordpress) role's install
guard is `wp_installed.rc != 0`, so on every later run the task is skipped.
Whatever URL is recorded on the first run is the URL the site keeps.

`wp_site_url` resolves to `https://…` whenever `enable_tls` is true. So if the
install ran inside the `wordpress` role — step 3, before `tls` in step 4 — it
would record an https address before any certificate existed. That is harmless
when certbot then succeeds, and it is a dead site when certbot does not:
WordPress redirects every visitor to a port nothing is listening on.

Moving the install after `tls` means the certificate is real before the address
is written, so the recorded URL is true the first time and never needs
correcting.

When this split was made, `tls` could not move ahead of `wordpress` instead:
certbot validated over HTTP and needed the nginx vhost that role renders.
Validation is DNS-01 now and needs nothing from the vhost, so the two roles
could be reordered and this one folded back in. That has not been done.

## Ordering

Deliberately **not** tagged `wordpress`. If it were, `--tags wordpress` would run
the prepare step and the install while skipping `tls` in between — recreating the
exact problem this role exists to avoid.

Consequence: `--tags wordpress` no longer installs WordPress. A first run needs
the full `site.yml`, which is already the documented first-run path.

## Key variables

| Variable | Purpose |
|---|---|
| `wp_auto_install` | `false` finishes setup in the browser instead — see [caching](../caching)'s note about re-running afterwards |
| `wp_site_url` | Derived from `enable_tls` and `domain`; used only here |
| `wp_admin_user`, `wp_admin_password`, `wp_site_title`, `admin_email` | Passed to `wp core install` |

Run alone: `ansible-playbook site.yml --tags install` (needs a certificate
already in place when `enable_tls` is true).
