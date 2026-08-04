output "public_ip" { value = module.wordpress.public_ip }
output "private_ip" { value = module.wordpress.private_ip }
output "security_group_id" { value = module.wordpress.security_group_id }
output "backup_bucket" { value = module.wordpress.backup_bucket }
output "vpc_id" { value = module.wordpress.vpc_id }
output "private_subnet_id" { value = module.wordpress.private_subnet_id }
