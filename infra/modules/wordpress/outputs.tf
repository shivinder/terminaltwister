output "public_ip" {
  description = "Elastic IP — use in ansible/inventory/hosts.ini and DNS A records"
  value       = aws_eip.wordpress.public_ip
}

output "private_ip" {
  description = "Instance private IP — WordPress connects to MariaDB on this address"
  value       = aws_instance.wordpress.private_ip
}

output "instance_id" {
  value = aws_instance.wordpress.id
}

output "security_group_id" {
  description = "Informational — CI deploy jobs resolve this at run time via the wp-<env>-sg Name tag"
  value       = aws_security_group.wordpress.id
}

output "backup_bucket" {
  value = aws_s3_bucket.backups.bucket
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "Reserved for the future dedicated DB instance"
  value       = aws_subnet.private.id
}
