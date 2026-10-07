# Role: base_hardening (Step 1)

OS baseline and access hardening.

## What it does

- `apt dist-upgrade` + enables unattended security upgrades
- Installs the baseline packages, including three that Debian's cloud image leaves out and the later roles rely on: `nftables` (fail2ban bans through it), `logrotate` and `acl`
- Creates a non-root sudo user (`system_user`) with your SSH public key
- Hardens sshd: no root login, no password auth, key-only, MaxAuthTries 3
- ufw: default deny incoming, allow SSH/80/443
- fail2ban with an sshd jail

## Key variables (group_vars/all/main.yml)

| Variable | Purpose |
|---|---|
| `system_user` / `system_user_ssh_key` | Admin user and its public key |
| `system_user_nopasswd_sudo` | Passwordless sudo (default true) |
| `ssh_port` | Port opened in ufw and watched by fail2ban |
| `timezone` | System timezone |

## Notes

- ufw complements the EC2 security group; keep 22 restricted to your IP at the SG level (or use SSM Session Manager and close it entirely).
- Password auth is disabled — make sure your key works **before** running this role.

Run alone: `ansible-playbook site.yml --tags base`
