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
├── modules/wordpress/     # VPC, subnets, SG, EC2, EIP, S3, IAM
│   ├── main.tf            # VPC, public + private subnets, IGW, routing
│   ├── security.tf        # security group (restricted)
│   ├── ec2.tf             # Ubuntu 26.04 LTS instance + Elastic IP
│   ├── s3.tf              # backup bucket (versioned, lifecycle, private)
│   ├── iam.tf             # instance role: s3 backup write, optional CloudWatch
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
- **Two environments, one module.** `test` has TLS/Let's Encrypt turned OFF
  (`enable_tls: false` in `ansible/group_vars/test.yml`) so deploys there never
  consume LE rate limits or affect production. Distinct VPC CIDRs allow future
  peering.

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
terraform output    # public_ip, private_ip, security_group_id, backup_bucket
```

**What a clean first apply looks like:** ~18 resources added, none changed or
destroyed — VPC, IGW, two subnets, route table + association, security group, EC2,
EIP + association, five S3 resources, three IAM resources. A wildly different count
means something is off; read the diff before continuing.

**If apply fails with `BucketAlreadyExists`:** S3 bucket names are globally unique
across all of AWS, so `terminaltwister-tfstate` or `terminaltwister-backups-test`
may already be taken by another account. Pick a different name and change it in
**two** places — the Terraform config and `backup_s3_bucket_name` in
`ansible/group_vars/<env>.yml` (see the sync table below).

**Cost.** A running environment is roughly US$8–10/month: `t4g.micro` (test) or
`t4g.small` (production), a 20 GB gp3 volume, and the Elastic IP — AWS bills every
public IPv4 address hourly, including EIPs attached to a running instance.

## Values that must stay in sync with Ansible

| Terraform (envs/*/main.tf) | Ansible |
|---|---|
| `vpc_cidr` | `vpc_cidr` in `group_vars/<env>.yml` (ufw + DB user host pattern) |
| `backup_bucket_name` | `backup_s3_bucket_name` in `group_vars/<env>.yml` |
| output `public_ip` | `ansible_host` in `inventory/hosts.ini` + DNS A records |
| SG Name tag `wp-<env>-sg` | Deploy jobs resolve the SG ID by this tag at run time |

## After apply

1. Put `public_ip` into `ansible/inventory/hosts.ini` and your DNS
   (A records for the apex and `www` in production; `test.` for test).
2. Run the `deploy-test` / `deploy-production` CI job — it resolves the
   security group by tag automatically, no CI variable needed.

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
