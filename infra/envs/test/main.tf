# Test environment — test.terminaltwister.com
# TLS is ON here (enable_tls: true in ansible/group_vars/test.yml), with a
# certificate covering test.terminaltwister.com alone. Production sends HSTS
# with includeSubDomains, which covers this name too, so anything short of real
# HTTPS is unreachable from a browser that has visited production.

module "wordpress" {
  source = "../../modules/wordpress"

  environment = "test"

  # Distinct CIDRs from production (10.0.0.0/16).
  # Must match vpc_cidr in ansible/group_vars/test.yml.
  vpc_cidr            = "10.10.0.0/16"
  public_subnet_cidr  = "10.10.1.0/24"
  private_subnet_cidr = "10.10.2.0/24"

  instance_type      = "t4g.micro" # Graviton (arm64), smaller/cheaper than production
  key_name           = var.key_name
  backup_bucket_name = "terminaltwister-backups-test"
  enable_cloudwatch  = false

  # Test is built to be destroyed and rebuilt from CI, and the bucket is
  # versioned — without this, the first `terraform destroy` after a nightly
  # backup has run fails with BucketNotEmpty. Production deliberately leaves
  # this at its default of false.
  backup_bucket_force_destroy = true

  # Empty by default, so no SNS topic and no alarm are created here.
  alarm_email = var.alarm_email

  # No snapshots: test is meant to be destroyed and rebuilt, and everything on
  # it comes back from the playbook. Set this to 1 temporarily when rehearsing
  # the volume-swap restore — better to practise here than on production.
  snapshot_retention_days = 0

  # Optionally restrict test web access to your own IP:
  # allowed_web_cidrs = ["203.0.113.10/32"]
}
