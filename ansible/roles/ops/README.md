# Role: ops (Step 7)

Ongoing operations: backups, restore, log rotation, monitoring.

## What it does

- **Backups** — nightly cron (`backup_cron_hour`), three archives per run, uploaded to S3 when `backup_s3_bucket` is set and pruned locally after `backup_retention_days`:
  - `db_*.sql.gz` — gzipped `mysqldump`, incl. routines/triggers
  - `wp-content_*.tar.gz` — themes, plugins, uploads
  - `config_*.tar.gz` — `wp-config.php` plus `/etc/letsencrypt` (the latter only when `enable_tls`). The only copy of the salts, which Ansible writes once and never rotates. See "Rebuilding from scratch" below — this archive is **not** restored by `wp-restore.sh`, deliberately. It holds the DB password and TLS private keys, so it is one more reason the bucket must stay private.

  The script:
  - takes a `flock` so runs never overlap
  - verifies the DB and wp-content archives (`gzip -t` + minimum-size check) before upload. The config archive gets `gzip -t` and a non-empty test but not `backup_min_bytes` — with TLS off it is a single ~1 KB file in a zero-padded tar, which gzips to about 1000 bytes and would trip a floor meant for catching an empty `mysqldump`
  - on ANY failure logs `ERROR: backup FAILED` and publishes `BackupSuccess=0` (success publishes `1`) to namespace `TerminalTwister/Backups`, dimension `Environment={{ environment_name }}`. Published unconditionally — this used to be gated on `enable_cloudwatch` and rendered as a no-op, which is why failed backups went unnoticed.
- **Restore** — `/usr/local/bin/wp-restore.sh [TIMESTAMP]` restores DB + wp-content from local or S3 backups, with verification and a confirmation prompt; previous wp-content is kept aside. Run without args to list backups. It never touches the config archive, and says so on the way out. Test restores periodically!
- **Log rotation** — for the backup log (nginx/PHP logs are rotated by their packages)
- **CloudWatch agent** (optional, `enable_cloudwatch: true`) — ships nginx access/error, wp-backup, and fail2ban logs (retention `cloudwatch_log_retention_days`) plus memory/disk metrics. Agent version pinnable via `cloudwatch_agent_version`; only downloaded when absent or pin mismatches.

## Key variables

| Variable | Purpose |
|---|---|
| `backup_s3_bucket_name` | per env: `terminaltwister-backups` / `-test` — empty string skips S3 |
| `backup_local_dir`, `backup_retention_days`, `backup_cron_hour` | Backup behavior |
| `backup_min_bytes` | Fail the backup if the DB or wp-content archive is smaller than this. Not applied to the config archive — see above |
| `environment_name` | CloudWatch dimension on `BackupSuccess`; must match `environment` in `infra/envs/<env>/main.tf` |
| `enable_cloudwatch` | Install and configure the CloudWatch agent. Does **not** gate `BackupSuccess` |
| `cloudwatch_log_retention_days` | Log group retention (cost control) |
| `cloudwatch_agent_version` | Pin agent build for reproducible deploys (`latest` by default) |

Role defaults live in `defaults/main.yml`; edit `group_vars/all/main.yml` to change them.

## AWS prerequisites (Terraform side)

- Instance profile with `s3:PutObject` on the backup bucket (restore also needs `s3:GetObject`/`s3:ListBucket`)
- `cloudwatch:PutMetricData`, scoped to the `TerminalTwister/*` namespace — granted unconditionally in `infra/modules/wordpress/iam.tf`
- The alarm on `BackupSuccess` lives in `infra/modules/wordpress/monitoring.tf`. It uses `treat_missing_data = "breaching"`, so it catches a backup that never ran (dead instance, broken cron, full disk) as well as one that failed. Needs `alarm_email` set, and the SNS subscription confirmed by hand — see `infra/README.md`.
- For the CloudWatch agent: `CloudWatchAgentServerPolicy` on the instance role (covers `logs:PutRetentionPolicy` used above)
- Nightly EBS snapshots of the root volume are handled by `infra/modules/wordpress/snapshots.tf` (DLM, 04:00 UTC, production only) — they cover the machine, where these backups cover the content. Restore procedure in `infra/README.md`
- Still outstanding: **periodic test restores**. Neither backup is proven until one has been restored

Run alone: `ansible-playbook site.yml --tags ops`

## Rebuilding from scratch

If the instance is gone rather than merely broken: `terraform apply`, then a full
playbook run, then `wp-restore.sh TIMESTAMP` for the database and `wp-content`.

That leaves one manual step, and the reason it is manual matters. **Do not copy
`wp-config.php` out of `config_*.tar.gz` over the newly generated one.**
`wp_db_host` is `{{ ansible_default_ipv4.address }}` — the instance's *private
IP* — and a rebuilt instance has a different one, so the restored file points
WordPress at a dead address and the failure reads as a broken database rather
than a bad restore.

Instead, keep the config Ansible just wrote and lift only the salts into it:

```bash
mkdir -p /tmp/cfg && tar xzf config_TIMESTAMP.tar.gz -C /tmp/cfg
# copy ONLY the define('AUTH_KEY'…) … define('NONCE_SALT'…) block into
# /var/www/<domain>/wp-config.php, leaving every other line alone
rm -rf /tmp/cfg      # it holds the DB password and TLS private keys
```

Those salts are what keep logged-in sessions valid and what makes any
`AUTH_KEY`-encrypted plugin data readable again. `wp-restore.sh` prints this same
reminder when it finishes. If you also want the old TLS certs rather than letting
certbot re-issue (rate limits), `cp -a /tmp/cfg/letsencrypt /etc/` before nginx
reloads.

If the volume is merely corrupt rather than the whole instance gone, don't do any
of this — restore the nightly EBS snapshot instead. That path is faster and keeps
the config as it was. See `infra/README.md`.
