# Production environment — terminaltwister.com
# TLS (Let's Encrypt) is ON for this environment: see ansible/group_vars/production.yml

module "wordpress" {
  source = "../../modules/wordpress"

  environment = "production"

  # Distinct CIDRs from test (10.10.0.0/16) so the VPCs could be peered later.
  # Must match vpc_cidr in ansible/group_vars/production.yml.
  vpc_cidr            = "10.0.0.0/16"
  public_subnet_cidr  = "10.0.1.0/24"
  private_subnet_cidr = "10.0.2.0/24"

  instance_type      = "t4g.small" # Graviton (arm64)
  key_name           = var.key_name
  backup_bucket_name = "terminaltwister-backups"
  enable_cloudwatch  = false
}
