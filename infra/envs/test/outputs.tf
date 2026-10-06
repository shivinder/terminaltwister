output "public_ip" { value = module.wordpress.public_ip }
output "dns_record" { value = module.wordpress.dns_record }
output "private_ip" { value = module.wordpress.private_ip }
# Needed by the volume-swap restore in infra/README.md, which is built entirely
# around the instance ID.
output "instance_id" { value = module.wordpress.instance_id }
output "security_group_id" { value = module.wordpress.security_group_id }
output "backup_bucket" { value = module.wordpress.backup_bucket }
output "backup_alerts" { value = module.wordpress.backup_alerts }
output "root_volume_snapshots" { value = module.wordpress.root_volume_snapshots }
output "vpc_id" { value = module.wordpress.vpc_id }
output "private_subnet_id" { value = module.wordpress.private_subnet_id }
