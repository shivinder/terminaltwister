# initial-tasks — one-time bootstrap

Creates the `terminaltwister-tfstate` S3 bucket (versioned, encrypted,
private, 90-day retention of old state versions) that `envs/test` and
`envs/production` use as their state backend.

## Why this is separate

A Terraform backend must exist before `terraform init` of the configs that
use it — so the bucket can't be created by those configs themselves. This
bootstrap config breaks the cycle: it uses **local state** (a
`terraform.tfstate` file in this directory) and is run once, by hand.

The backup buckets are NOT created here — they belong to each environment
and are managed by the `wordpress` module.

## Usage (once, locally)

```bash
cd infra/initial-tasks
terraform init
terraform apply
```

Not wired into CI on purpose: CI runners have no way to persist this
directory's local state between runs.

## About the local state file

The state produced here describes one bucket and contains no secrets.
Recommended: **commit `terraform.tfstate` in this directory to the repo**
so the bootstrap stays reproducible for everyone. (`.gitignore` here only
excludes `.terraform/`.)

If the state file is ever lost, don't re-apply blindly (the bucket already
exists) — re-import instead:

```bash
terraform import aws_s3_bucket.tfstate terminaltwister-tfstate
```

`prevent_destroy` is set on the bucket: `terraform destroy` will refuse to
delete it, since that would orphan the state of every environment.
