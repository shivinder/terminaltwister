# infra — Terraform

Provisions the AWS infrastructure for terminaltwister.com as a reusable module
with two environments. Configuration management is handled by Ansible in
`../ansible/`; both are driven by `.gitlab-ci.yml` at the repo root.

## Layout

```
infra/
├── initial-tasks/         # one-time bootstrap: creates the tfstate bucket (local state)
├── scripts/
│   └── preflight.sh       # pre-apply checks: creds, key pair, buckets, versions
├── modules/wordpress/     # VPC, subnets, SG, EC2, EIP, S3, IAM, alerting, snapshots, DNS record
│   ├── main.tf            # VPC, public + private subnets, IGW, routing
│   ├── security.tf        # security group (restricted)
│   ├── ec2.tf             # Ubuntu 26.04 LTS instance + Elastic IP
│   ├── s3.tf              # backup bucket (versioned, lifecycle, private, TLS-only)
│   ├── iam.tf             # instance role: s3 backup write, metric publish, optional CW agent
│   ├── monitoring.tf      # SNS topic + backup-failure alarm (only if alarm_email set)
│   ├── snapshots.tf       # DLM nightly root-volume snapshots (only if retention > 0)
│   ├── dns.tf             # Route53 A record → Elastic IP (only if dns_name set)
│   ├── variables.tf
│   └── outputs.tf
└── envs/                  # each env: providers.tf (terraform+backend+provider),
    │                      # variables.tf, outputs.tf, main.tf (module call)
    ├── test/              # 10.10.0.0/16, t4g.micro, terminaltwister-backups-test
    └── production/        # 10.0.0.0/16,  t4g.small, terminaltwister-backups
```

## Design decisions

- **Public + private subnet.** WordPress (and, for now, its MariaDB) run on one
  EC2 in the public subnet. The private subnet is provisioned but empty —
  reserved for a dedicated DB instance later. No NAT gateway yet (costs money,
  nothing uses it).
- **DB over private IP.** Ansible binds MariaDB to the instance's private IP and
  points WordPress at it (`wp_db_host`). Moving the DB to its own instance later
  is a one-variable change plus a data migration — no application rework.
- **Restricted security group.** 80/443 from `allowed_web_cidrs` (default open;
  restrict for test), 3306 only from members of the same SG (`self`) — ready for
  the future DB host, SSH closed (the CI deploy job allowlists the runner IP per
  run; set `admin_ssh_cidrs` for a permanent rule), IMDSv2 enforced, EBS encrypted.
- **Two environments, one module.** Both run TLS, each with its own Let's
  Encrypt certificate — `test` covers `test.terminaltwister.com` alone rather
  than sharing production's. Production sends HSTS with `includeSubDomains`,
  which covers every name under the apex, so a plain-HTTP test site would be
  unreachable from any browser that had visited production. Separate
  certificates also keep production's private key off the disposable box and let
  each host renew independently via HTTP-01. Distinct VPC CIDRs allow future
  peering.
- **Two recovery layers, on purpose.** The nightly Ansible backup puts content
  in S3 with 90 days of depth; DLM snapshots keep the last 7 days of the whole
  disk. Neither replaces the other — S3 is how you get last month's uploads
  back, snapshots are how you get a bootable machine back within the hour. Both
  are off by default at the module level and turned on per environment, so test
  costs nothing. Alerting on the first one is `monitoring.tf`; see below.

## State backend

State lives in the S3 bucket **terminaltwister-tfstate** (ap-southeast-2),
created once by `initial-tasks/` (versioned, encrypted, private — see its
README), one key per environment: `test/terraform.tfstate`,
`production/terraform.tfstate`.
Locking uses S3-native lockfiles (`use_lockfile`, a Terraform 1.10+ feature) —
no DynamoDB table needed. The backend is hardcoded in each env's `providers.tf`,
so `terraform init` needs no extra flags, locally or in CI.

These configs declare `required_version = ">= 1.15"` and CI runs the matching
`hashicorp/terraform:1.15` image. Bump both together, or `terraform init` fails
on the version constraint.

## Running

Preflight — confirm everything an apply depends on is in place:

```bash
./infra/scripts/preflight.sh test        # or: production
```

Checks tooling versions, AWS credentials and region, the EC2 key pair, both S3
bucket names, `terraform fmt`, and whether SSH will be reachable. Exits non-zero
on anything blocking, and prints the command that fixes it. Every expectation is
read out of the Terraform config, so the script cannot drift from it.

First time only — two prerequisites.

**1. The EC2 key pair.** `key_name` defaults to **`kp-sydney-01`**, which already
exists in the account — nothing to do. Note this is the AWS *key pair name*, not
the `.pem` filename you downloaded. Deliberately not managed by Terraform: the
private key would be written into state.

Use the matching private key for the `SSH_PRIVATE_KEY` CI variable. To point at
a different pair, set `TF_VAR_key_name` (or edit `key_name` in
`envs/<env>/variables.tf`).

Only when building a fresh account:

```bash
aws ec2 create-key-pair --key-name kp-sydney-01 \
  --query 'KeyMaterial' --output text > ~/.ssh/kp-sydney-01.pem
chmod 600 ~/.ssh/kp-sydney-01.pem
```

**2. The state bucket:**

```bash
cd infra/initial-tasks && terraform init && terraform apply
```

**Decide SSH access before you apply.** `admin_ssh_cidrs` defaults to `[]`, so the
security group opens **no SSH port at all** — deliberate, because the CI deploy job
allowlists the runner's IP per run and revokes it afterwards. If you intend to run
Ansible from your own machine, set it in `envs/<env>/main.tf` first; otherwise you
apply, discover you cannot connect, and have to apply a second time:

```hcl
  admin_ssh_cidrs = ["203.0.113.10/32"] # your IP: curl https://checkip.amazonaws.com
```

Then, via CI (preferred): pipeline stages `tf-validate` → `tf-plan` → `tf-apply`
(manual), one job per environment.

Locally (needs AWS credentials with access to the state bucket):

```bash
cd infra/envs/test
terraform init
terraform plan
terraform apply
terraform output    # public_ip, dns_record, private_ip, instance_id, security_group_id,
                    # backup_bucket, backup_alerts, root_volume_snapshots
```

**What a clean first apply looks like:** 21 resources added, none changed or
destroyed — VPC, IGW, two subnets, route table + association, the VPC's adopted
default SG and default route table, security group, EC2, EIP + association, six
S3 resources, three IAM resources. Add one where `dns_name` is set, as test has
it — the Route53 A record. Add three more when `alarm_email` is set — an SNS
topic, its email subscription and the backup alarm — and three more again when
`snapshot_retention_days` is above 0, as production has it: a DLM policy, its
service role and that role's policy attachment. Test creates neither of those
sets and lands on 22; production, with both and no `dns_name` until cutover, on
27. A wildly different count means something is off; read the diff before
continuing.

**If apply fails with `BucketAlreadyExists`:** S3 bucket names are globally unique
across all of AWS, so `terminaltwister-tfstate` or `terminaltwister-backups-test`
may already be taken by another account. Pick a different name and change it in
**two** places — the Terraform config and `backup_s3_bucket_name` in
`ansible/group_vars/<env>.yml` (see the sync table below).

**Cost.** Every figure below is in Australian dollars, converted from AWS's
published ap-southeast-2 prices at **US$1 = A$1.41 (August 2026)**. AWS lists and
bills ap-southeast-2 in USD, so what lands on the statement moves with the
exchange rate — and an Australian account adds 10% GST on top of these numbers.

A running environment is roughly A$11–14/month: `t4g.micro` (test) or
`t4g.small` (production), a 20 GB gp3 volume, and the Elastic IP — AWS bills every
public IPv4 address hourly, including EIPs attached to a running instance.

Backup alerting adds at most A$0.56/month — one custom metric (A$0.42) and one
standard-resolution alarm (A$0.14); SNS email is free below 1,000 notifications
a month. CloudWatch's free tier covers 10 custom metrics and 10 alarms, so if the
account isn't already using that allowance the real figure is zero. Nothing here
scales with traffic.

Root-volume snapshots add roughly A$0.50/month for a small site. Snapshot
storage in ap-southeast-2 is A$0.078/GB-month, snapshots are incremental, and
they bill on blocks actually written rather than the 20 GB volume size — so a
first snapshot of a ~5 GB install is about A$0.39 and six daily deltas add a
few cents. DLM itself is free.

That figure scales with `wp-content`, and faster than you would expect: the
nightly backup keeps `backup_retention_days` (7) local tarballs on the very
volume being snapshotted, so every night writes a fresh full-size tarball into
the next snapshot's delta. A site with 3 GB of uploads lands nearer
A$2.05/month. Two knobs if that matters: lower `backup_retention_days` (S3
still holds 90 days, and `wp-restore.sh` pulls from S3 automatically when a file
is missing locally), or lower `snapshot_retention_days`. Note that at 3 GB of
uploads, seven local tarballs is ~20 GB on a 20 GB root volume — a disk-full
risk quite apart from snapshot cost, and one the backup alarm above will catch.

## Values that must stay in sync with Ansible

| Terraform (envs/*/main.tf) | Ansible |
|---|---|
| `vpc_cidr` | `vpc_cidr` in `group_vars/<env>.yml` (ufw + DB user host pattern) |
| `backup_bucket_name` | `backup_s3_bucket_name` in `group_vars/<env>.yml` |
| `dns_name` | `domain` in `group_vars/<env>.yml` (the name the certificate is issued for) |
| output `public_ip` | `ansible_host` in `inventory/hosts.ini` (local runs) + the DNS A record where `dns_name` is unset |
| SG Name tag `tt-wp-<env>-sg` | Deploy jobs resolve the SG ID by this tag at run time |
| `environment` | `environment_name` in `group_vars/<env>.yml` (backup alarm's CloudWatch dimension) |

## After apply

1. DNS. Where `dns_name` is set (test), the apply has already done it: `dns.tf`
   ties an A record in the `terminaltwister.com` Route53 zone to the Elastic
   IP, so a destroy/recreate cycle — which allocates a fresh EIP every time —
   needs nothing done by hand. `terraform output dns_record` says which you
   got. The zone itself is made by hand and only looked up; it also carries the
   mail records, and no environment's destroy touches it.

   Where `dns_name` is not set (production, until cutover), point the apex A
   record at `public_ip` yourself; `www` is a CNAME to the apex and follows.
   The `tls` role validates over HTTP-01 and the smoke test fetches the site by
   name, so both need the record live before deploy. Setting
   `dns_name = "terminaltwister.com"` in `envs/production/main.tf` hands the
   apex to Terraform, and the next apply repoints the live site at this
   instance — so that change is the cutover, not something to do ahead of it.

   `ansible/inventory/hosts.ini` no longer needs touching for CI: the deploy
   jobs resolve the instance by its `tt-wp-<env>` Name tag and generate their
   own inventory. That file is for local runs only.
2. Run the `deploy-test` / `deploy-production` CI job — it resolves the
   security group and the instance IP by tag automatically, no CI variable
   needed, and fails with one clear line if DNS isn't pointing at the box yet.
3. **Confirm the backup-alert subscription** — see below. Skip this and the
   alarm has nowhere to deliver.
4. Once a snapshot and a backup exist, **rehearse a restore of each** — see
   "Root volume snapshots" below and `ansible/roles/ops/README.md`. Neither is
   proven until it has been restored once.

### Backup alerting

The nightly backup publishes a `BackupSuccess` metric (namespace
`TerminalTwister/Backups`, dimension `Environment`). `monitoring.tf` alarms on it and
emails `alarm_email`, set in CI as `TF_VAR_alarm_email`. Leave it unset and
production applies with no alerting at all — `terraform output backup_alerts`
prints which of the two you got.

The alarm uses `treat_missing_data = "breaching"`, so it fires on *absence of
success* rather than on a reported failure. That is the point: a terminated
instance, a broken cron or a full disk never get to report anything, and those
are the failures that otherwise stay hidden until a restore.

Two behaviours that look like faults and aren't:

- **The subscription needs a human click.** AWS emails a confirmation link to
  `alarm_email` and the subscription stays `PendingConfirmation` until someone
  follows it. Terraform can't do this step, and an unconfirmed subscription is
  indistinguishable from a working one right up until the first alert vanishes.
  The link expires after three days; re-send with
  `aws sns subscribe --topic-arn <arn> --protocol email --notification-endpoint <you>`.
- **The alarm fires once, shortly after a first apply.** No backup has run yet,
  so there is no data, and no data is a breach. Treat it as a free end-to-end
  test of metric → alarm → SNS → inbox. It clears after the first 03:00 run.

To prove the whole chain without waiting for a real failure:

```bash
aws cloudwatch set-alarm-state --alarm-name tt-wp-production-backup-failed \
  --state-value ALARM --state-reason "testing delivery"
# ...then put it back; the OK transition emails too, which is the point of ok_actions
aws cloudwatch set-alarm-state --alarm-name tt-wp-production-backup-failed \
  --state-value OK --state-reason "test complete"
```

### What the backup bucket holds

Three archives per night, under `<bucket>/<domain>/`:

| | |
|---|---|
| `db_TIMESTAMP.sql.gz` | `mysqldump` incl. routines and triggers |
| `wp-content_TIMESTAMP.tar.gz` | themes, plugins, uploads |
| `config_TIMESTAMP.tar.gz` | `wp-config.php` and `/etc/letsencrypt` |

The third one exists because nothing else copies it: Ansible writes
`wp-config.php` exactly once and never rotates the salts, so a rebuilt instance
gets *new* salts — logging every user out, and permanently orphaning any plugin
data encrypted with `AUTH_KEY`, no matter how good the database backup is.

**Consequence worth knowing:** that archive contains the database password and
the Let's Encrypt private keys, so the backup bucket is now a place secrets
live. It blocks public access on all four settings, is SSE-S3 encrypted and
versioned, carries a bucket policy denying any request that arrives over plain
HTTP (`aws:SecureTransport: false`), and is reachable only by the instance role
and account principals with S3 access — but a leak of it now costs more than it
used to. Versioning plus `noncurrent_version_expiration = 30` means deleted
copies linger 30 days.

`wp-restore.sh` never restores this archive; see `ansible/roles/ops/README.md`
for why restoring `wp-config.php` wholesale breaks the site, and what to do
instead.

### Root volume snapshots

`snapshots.tf` runs a DLM policy that snapshots every EBS volume tagged for this
environment at 04:00 UTC and keeps `snapshot_retention_days` of them (7 in
production, 0 — meaning off — in test). 04:00 is deliberate: the backup cron runs
at 03:00 on a UTC box, so the snapshot catches a disk holding that night's
finished archives without fighting `mysqldump` for I/O.

This covers what S3 cannot: a bootable machine. S3 gives 90 days of depth on the
content; snapshots give the last week of the whole disk.

These are **crash-consistent**, not application-consistent — equivalent to
pulling the power. InnoDB replays its redo log on the next boot and comes up
clean, which is what the redo log is for.

To restore one, swap the volume rather than launching a new instance — that
keeps the instance Terraform manages, and the Elastic IP is attached to the
*instance*, so DNS is untouched throughout:

```bash
# 1. Pick a snapshot. VolumeId matters: after any previous restore there is more
#    than one volume in this environment's history, and copy_tags gives every
#    snapshot the same Name — the source volume is the only thing telling them apart.
aws ec2 describe-snapshots --owner-ids self \
  --filters Name=tag:Name,Values=tt-wp-production-root \
  --query 'sort_by(Snapshots,&StartTime)[-5:].{Id:SnapshotId,When:StartTime,Vol:VolumeId}' \
  --output table

# 2. Identify the instance, and read its root device name — don't assume /dev/sda1.
#    The AZ is no longer a mystery: it is pinned as var.availability_zone.
INSTANCE=$(cd infra/envs/production && terraform output -raw instance_id)
aws ec2 describe-instances --instance-ids "$INSTANCE" \
  --query 'Reservations[0].Instances[0].{AZ:Placement.AvailabilityZone,Dev:RootDeviceName,Vol:BlockDeviceMappings[0].Ebs.VolumeId}'

# 3. Build a replacement volume in that AZ, tagged so the next apply sees no drift
aws ec2 create-volume --snapshot-id snap-xxx --availability-zone <AZ> \
  --volume-type gp3 --encrypted \
  --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=tt-wp-production-root},{Key=Project,Value=terminaltwister},{Key=Environment,Value=production},{Key=ManagedBy,Value=terraform}]'

# 4. Swap it in
aws ec2 stop-instances  --instance-ids "$INSTANCE" && aws ec2 wait instance-stopped --instance-ids "$INSTANCE"
aws ec2 detach-volume   --volume-id <old-vol> && aws ec2 wait volume-available --volume-ids <old-vol>
aws ec2 attach-volume   --volume-id <new-vol> --instance-id "$INSTANCE" --device <Dev>
aws ec2 start-instances --instance-ids "$INSTANCE"

# 5. Untag the old volume NOW — do not skip this. See "Retire the old volume" below.
aws ec2 delete-tags --resources <old-vol> --tags Key=Project Key=Environment Key=ManagedBy
```

**Retire the old volume.** Step 5 is not tidying up, it is part of the restore.
`snapshots.tf` selects by tag, re-evaluated every night against whatever carries
those tags at that moment — and detaching a volume changes its state, not its
tags. Leave the old one tagged and DLM keeps snapshotting the disk you just
abandoned, forever. Retention is per volume (`retain_rule.count` is *"the number
of snapshots to retain for each volume"*), so you end up with seven snapshots of
the live disk and seven of the dead one, all carrying the same `Name` and
`SnapshotType`. The cost is real — a detached 20 GB gp3 volume is about
A$2.71/month, against the A$0.50 this whole feature is meant to cost — but the
worse part is step 1: the next restore has to choose between two indistinguishable
lineages, one of which is the disk that failed. Nothing warns you, either.
Terraform never had the old volume in state, so `plan` stays clean.

There is no way to fix this in the policy: DLM's `Exclusions` are for default
policies only, and `ExcludeBootVolume` applies to `INSTANCE` policies, so a custom
`VOLUME` policy has no attachment-state filter at all. Untagging is the lever.

Untag immediately, then delete once you trust the restore. Untagging stops the
snapshotting but not the A$2.71 — a detached volume bills the same as an attached
one, so this is worth keeping only as long as you might still need to read it:

```bash
# Once the site is confirmed healthy:
aws ec2 delete-volume --volume-id <old-vol>

# DLM prunes only when it creates a NEW snapshot, so the old volume's snapshots
# stop expiring the moment you untag it. Clean them up by source volume:
aws ec2 describe-snapshots --owner-ids self \
  --filters Name=volume-id,Values=<old-vol> --query 'Snapshots[].SnapshotId' --output text
```

**Rehearse this once before you need it.** Set `snapshot_retention_days = 1` in
`envs/test/main.tf`, apply, wait for a snapshot, do the swap against the test
instance, then set it back to 0. It costs pennies and proves the procedure on a
box nobody minds breaking. Setting it back to 0 destroys the policy, which strands
the rehearsal snapshot for the same reason — clear it out with the cleanup command
under "Tearing down".

## Tearing down

```bash
cd infra/envs/test && terraform destroy
```

Safe to run against one environment: the other is untouched, and the state bucket
survives because it lives in the separate `initial-tasks/` config behind
`prevent_destroy`.

**The backup bucket will block the destroy once it holds anything.** No bucket in
this repo sets `force_destroy`, so S3 refuses to delete a non-empty one and
Terraform fails with `BucketNotEmpty`. That is intentional — it means a stray
`destroy` cannot silently take your backups with it. Versioning is on, so emptying
it requires removing old versions and delete markers too, not just current objects:

```bash
aws s3 rm s3://terminaltwister-backups-test --recursive
aws s3api delete-objects --bucket terminaltwister-backups-test \
  --delete "$(aws s3api list-object-versions \
    --bucket terminaltwister-backups-test \
    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json)"
```

Repeat the second command for `DeleteMarkers[]` if any remain, then re-run
`terraform destroy`. Export anything you want to keep first.

**Snapshots outlive the destroy, and then nobody prunes them.** DLM creates
snapshots; Terraform only manages the *policy*. Destroying the environment
removes the policy, so retention stops running and the last few snapshots sit
there billing quietly with nothing left to expire them. That is the right
default — a stray `destroy` should not take your last disk image with it — but
it does mean cleaning up by hand once you are sure:

```bash
aws ec2 describe-snapshots --owner-ids self \
  --filters Name=tag:Project,Values=terminaltwister Name=tag:Environment,Values=test \
  --query 'Snapshots[].SnapshotId' --output text | xargs -n1 aws ec2 delete-snapshot --snapshot-id
```
