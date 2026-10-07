output "public_ip" {
  description = "Elastic IP — use in ansible/inventory/hosts.ini for local runs, and in the DNS A record when dns_name is unset"
  value       = aws_eip.wordpress.public_ip
}

# Same reasoning as backup_alerts below: make "DNS is still a manual step" a
# line in the tf-apply log rather than a deploy that fails its DNS check.
output "dns_record" {
  description = "Name Terraform keeps pointed at the Elastic IP, or a warning when dns_name is unset"
  value       = try(aws_route53_record.wordpress[0].fqdn, "DISABLED — point the A record at public_ip by hand before deploying")
}

# Same reasoning again: without the policy a deploy with enable_tls fails inside
# certbot, on an AccessDenied that does not say which variable was left empty.
output "certificate_names" {
  description = "Names whose _acme-challenge record the instance role may write, or a warning when certificate_names is empty"
  value = try(
    "${join(", ", var.certificate_names)} (${aws_iam_role_policy.acme_dns[0].name})",
    "DISABLED — the instance cannot answer Let's Encrypt's DNS challenge; set certificate_names before deploying with enable_tls"
  )
}

output "private_ip" {
  description = "Instance private IP — WordPress connects to MariaDB on this address"
  value       = aws_instance.wordpress.private_ip
}

output "instance_id" {
  value = aws_instance.wordpress.id
}

output "security_group_id" {
  description = "Informational — CI deploy jobs resolve this at run time via the tt-wp-<env>-sg Name tag"
  value       = aws_security_group.wordpress.id
}

output "backup_bucket" {
  value = aws_s3_bucket.backups.bucket
}

# Printed by the tf-apply CI job, so "alerting is off" is visible in the job log
# instead of being discovered the first time a backup fails unnoticed.
output "backup_alerts" {
  description = "SNS topic receiving backup-failure alerts, or a warning when alarm_email is unset"
  # try() rather than a conditional on var.alarm_email: indexing a count=0
  # resource is the kind of thing that only fails at apply time.
  value = try(aws_sns_topic.alerts[0].arn, "DISABLED — set TF_VAR_alarm_email to be told when backups fail")
}

# Same reasoning as backup_alerts: make "there are no snapshots" a line in the
# tf-apply log rather than something you find out while trying to restore.
output "root_volume_snapshots" {
  description = "DLM policy taking nightly root-volume snapshots, or a warning when snapshot_retention_days is 0"
  value = try(
    "${aws_dlm_lifecycle_policy.root_volume[0].id} (${var.snapshot_retention_days}-day retention)",
    "DISABLED — no EBS snapshots; the root volume is the only copy of this machine"
  )
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
