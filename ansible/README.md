# WordPress on EC2 — Ansible

Provisions a public-facing, hardened, cached WordPress blog on **Ubuntu 26.04 LTS** (EC2 instance already created by Terraform). Stack: **nginx + MariaDB + PHP-FPM**, Let's Encrypt TLS, OPcache + Redis object cache + nginx FastCGI page cache.

## Layout

```
ansible/
├── ansible.cfg
├── site.yml                  # single entry point for all steps
├── requirements.yml          # required Ansible collections
├── inventory/hosts.ini       # point at your EC2 instance
├── group_vars/all/
│   ├── main.yml              # all tunable parameters
│   └── vault.yml             # secrets (encrypt with ansible-vault)
└── roles/
    ├── base_hardening/       # Step 1: updates, SSH, ufw, fail2ban
    ├── lemp_stack/           # Step 2: nginx, MariaDB, PHP-FPM
    ├── wordpress/            # Step 3: WordPress, WP-CLI, vhost
    ├── tls/                  # Step 4: Let's Encrypt
    ├── wp_install/           # Step 5: wp core install (after the cert exists)
    ├── caching/              # Step 6: OPcache, Redis, FastCGI cache
    ├── wp_hardening/         # Step 7: WP/nginx hardening, rate limits
    └── ops/                  # Step 8: backups, monitoring
```

## Prerequisites

- Control machine: ansible-core >= 2.20 — Ubuntu 26.04 runs Python 3.14, which older releases cannot manage (the runner image uses 2.21)
- EC2 instance running Ubuntu 26.04, reachable via SSH (user `ubuntu`, key auth)
- EC2 security group: inbound 80, 443 open; 22 restricted to your IP
- DNS A record for `domain` pointing at the instance's Elastic IP (required before the `tls` role) — `tf-apply` creates it where `dns_name` is set in `infra/envs/<env>/main.tf`
- Instance profile with `s3:PutObject` on the backup bucket (S3 backups) and
  `cloudwatch:PutMetricData` on `TerminalTwister/*` — the latter is granted
  unconditionally, because the backup reports success through it whether or not
  the CloudWatch agent is enabled. Both come from `infra/modules/wordpress/iam.tf`

## Usage

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml

# 1. Edit inventory/hosts.ini with your EC2 IP + key
# 2. Edit group_vars/all/main.yml (domain, ssh key, etc.)
# 3. Set secrets, then encrypt:
ansible-vault encrypt group_vars/all/vault.yml

# Run everything:
ansible-playbook site.yml --ask-vault-pass

# Or one step at a time (tags: base, lemp, wordpress, tls, install, caching,
# hardening, ops). Note `wordpress` no longer installs WordPress — that is
# `install`, which runs after `tls` so the site URL is only recorded once a
# certificate exists. A first run needs the full site.yml regardless:
ansible-playbook site.yml --tags caching --ask-vault-pass
```

## Running without Ansible installed

**Docker (local, ad-hoc):**

```bash
cd ansible
make build                       # once, or after requirements.yml changes
KEY=~/.ssh/my-key.pem make deploy
make check                       # dry run
make deploy TAGS=caching         # single step
```

**GitLab CI (recommended for ongoing deploys):** `.gitlab-ci.yml` at the repo root builds the runner image, syntax-checks every push/MR, and offers a **manual** deploy job on the default branch. The deploy job temporarily allowlists the runner's IP on the EC2 security group for SSH, runs the playbook, and always revokes the rule afterwards. Required CI/CD variables are documented at the top of `.gitlab-ci.yml`. All are **protected**; `ANSIBLE_VAULT_PASSWORD`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_DEFAULT_REGION` are also **masked**. `SSH_PRIVATE_KEY` is a **File** variable and cannot be masked — GitLab rejects multi-line values there, so save it with visibility **Visible**. The security group is resolved at run time from its `tt-wp-<env>-sg` Name tag — no SG variable needed.

## Notes

- **Idempotent**: safe to re-run. Salts and certificates are generated once, not rotated — which makes them the one thing a rebuilt instance cannot reproduce, so the `ops` role copies `wp-config.php` and `/etc/letsencrypt` into the nightly backup. Restoring them has a trap worth reading before you need it: `roles/ops/README.md`, "Rebuilding from scratch".
- **Order matters on first run**: run the full `site.yml`. The nginx vhost is rendered HTTP-only until the `tls` role obtains a certificate, then re-rendered with TLS + HSTS redirect.
- The FastCGI page-cache directives live in the vhost template (`roles/wordpress/templates/wordpress.conf.j2`) and are toggled by `enable_fastcgi_cache`; the `caching` role owns OPcache, Redis, and gzip.
- ufw runs in addition to the EC2 security group (defense in depth).
- Each role has its own `README.md` with variables and details.
