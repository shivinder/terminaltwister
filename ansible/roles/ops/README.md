# Role: ops (Step 7)

Ongoing operations: backups, restore, log rotation, monitoring.

## What it does

- **Backups** — nightly cron (`backup_cron_hour`): gzipped `mysqldump` (incl. routines/triggers) + tarball of `wp-content`, uploaded to S3 when `backup_s3_bucket` is set, local copies pruned after `backup_retention_days`. The script:
  - takes a `flock` so runs never overlap
  - verifies both archives (`gzip -t` + minimum-size check) before upload
  - on ANY failure logs `ERROR: backup FAILED` and, with CloudWatch enabled, publishes `BackupSuccess=0` (success publishes `1`) — alarm on `< 1` or missing data
- **Restore** — `/usr/local/bin/wp-restore.sh [TIMESTAMP]` restores DB + wp-content from local or S3 backups, with verification and a confirmation prompt; previous wp-content is kept aside. Run without args to list backups. Test restores periodically!
- **Log rotation** — for the backup log (nginx/PHP logs are rotated by their packages)
- **CloudWatch agent** (optional, `enable_cloudwatch: true`) — ships nginx access/error, wp-backup, and fail2ban logs (retention `cloudwatch_log_retention_days`) plus memory/disk metrics. Agent version pinnable via `cloudwatch_agent_version`; only downloaded when absent or pin mismatches.

## Key variables

| Variable | Purpose |
|---|---|
| `backup_s3_bucket_name` | per env: `terminaltwister-backups` / `-test` — empty string skips S3 |
| `backup_local_dir`, `backup_retention_days`, `backup_cron_hour` | Backup behavior |
| `backup_min_bytes` | Fail backup if an archive is smaller than this |
| `enable_cloudwatch` | Install and configure the CloudWatch agent |
| `cloudwatch_log_retention_days` | Log group retention (cost control) |
| `cloudwatch_agent_version` | Pin agent build for reproducible deploys (`latest` by default) |

Role defaults live in `defaults/main.yml`; edit `group_vars/all/main.yml` to change them.

## AWS prerequisites (Terraform side)

- Instance profile with `s3:PutObject` on the backup bucket (restore also needs `s3:GetObject`/`s3:ListBucket`)
- For CloudWatch: `CloudWatchAgentServerPolicy` on the instance role (covers `PutMetricData` and `logs:PutRetentionPolicy` used above)
- Recommended: S3 lifecycle policy on the bucket, EBS snapshots via AWS Backup, CloudWatch alarm on the `BackupSuccess` metric

Run alone: `ansible-playbook site.yml --tags ops`
