# Test environment — test.terminaltwister.com
# TLS (Let's Encrypt) is OFF for this environment (enable_tls: false in
# ansible/group_vars/test.yml), so WordPress can be deployed and torn down
# here without consuming Let's Encrypt rate limits or touching production.

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

  # Optionally restrict test web access to your own IP:
  # allowed_web_cidrs = ["203.0.113.10/32"]
}
