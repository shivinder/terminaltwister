variable "environment" {
  description = "Environment name (test | production)"
  type        = string

  validation {
    condition     = contains(["test", "production"], var.environment)
    error_message = "environment must be 'test' or 'production'."
  }
}

# --- Network ---
variable "vpc_cidr" {
  description = "VPC CIDR. Must match vpc_cidr in ansible/group_vars/<env>.yml"
  type        = string
}

variable "public_subnet_cidr" {
  description = "Public subnet (WordPress EC2 lives here)"
  type        = string
}

variable "private_subnet_cidr" {
  description = "Private subnet — reserved for a future dedicated DB instance"
  type        = string
}

variable "availability_zone" {
  description = "AZ for both subnets, and therefore for the EBS root volume and every snapshot of it. Pinned rather than discovered — see main.tf."
  type        = string
  default     = "ap-southeast-2a"
}

# --- Compute ---
variable "instance_type" {
  description = "Must be an arm64 (Graviton) type — the AMI is arm64"
  type        = string
  default     = "t4g.small"
}

variable "key_name" {
  description = "Name of an existing EC2 key pair"
  type        = string
}

variable "root_volume_size" {
  type    = number
  default = 20
}

# --- Security ---
variable "allowed_web_cidrs" {
  description = "CIDRs allowed to reach 80/443. Restrict for test if desired."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "admin_ssh_cidrs" {
  description = "CIDRs permanently allowed SSH. Default none — the CI deploy job adds/revokes the runner IP per run."
  type        = list(string)
  default     = []
}

# --- Backups / monitoring ---
variable "backup_bucket_name" {
  description = "S3 bucket for WordPress backups. Must match backup_s3_bucket_name in ansible/group_vars/<env>.yml"
  type        = string
}

variable "backup_bucket_force_destroy" {
  description = <<-EOT
    Let `terraform destroy` delete the backup bucket along with every object and
    version inside it. Off by default so production cannot lose its backups to a
    stray destroy; on only for test, which exists to be torn down. Without this,
    destroy fails with BucketNotEmpty the moment one nightly backup has run.
  EOT
  type        = bool
  default     = false
}

variable "backup_expiration_days" {
  type    = number
  default = 90
}

variable "enable_cloudwatch" {
  description = "Attach CloudWatchAgentServerPolicy to the instance role"
  type        = bool
  default     = false
}

variable "snapshot_retention_days" {
  description = "Nightly EBS snapshots of the root volume, retained this many days. 0 (the default) creates no snapshot policy at all — see snapshots.tf."
  type        = number
  default     = 0

  # DLM caps retain_rule.count at 1000, and rejects a count below 1 — so 0 could
  # never reach the API anyway, which is what makes it a safe "off" value here.
  validation {
    condition     = var.snapshot_retention_days >= 0 && var.snapshot_retention_days <= 1000 && floor(var.snapshot_retention_days) == var.snapshot_retention_days
    error_message = "snapshot_retention_days must be a whole number from 0 (disabled) to 1000."
  }
}

variable "alarm_email" {
  description = "Where backup-failure alerts go. Empty (the default) creates no SNS topic and no alarm — see monitoring.tf."
  type        = string
  default     = ""

  # A typo here means alerts go nowhere and look exactly like alerts that were
  # never triggered, so it is worth catching at plan time rather than at 3am.
  validation {
    condition     = var.alarm_email == "" || can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.alarm_email))
    error_message = "alarm_email must be a valid email address, or empty to disable alerting."
  }
}

# --- DNS ---
variable "dns_name" {
  description = "Name to point at the Elastic IP. Must match domain in ansible/group_vars/<env>.yml. Empty (the default) creates no record — see dns.tf."
  type        = string
  default     = ""

  # Route53 rejects a name outside the zone too, but only at apply time, with
  # the rest of the environment already half built.
  validation {
    condition     = var.dns_name == "" || var.dns_name == var.dns_zone || endswith(var.dns_name, ".${var.dns_zone}")
    error_message = "dns_name must be dns_zone itself or a name under it, or empty to create no record."
  }
}

variable "dns_zone" {
  description = "Existing public Route53 hosted zone that dns_name and certificate_names live in. Looked up, never created or destroyed here."
  type        = string
  default     = "terminaltwister.com"
}

variable "certificate_names" {
  description = "Every name the Let's Encrypt certificate covers. Must match domain, plus www.domain when www_alias, in ansible/group_vars/<env>.yml. The instance role may write the _acme-challenge TXT record of each and nothing else in the zone. Empty (the default) grants no Route53 access — see iam.tf."
  type        = list(string)
  default     = []

  # A name outside the zone would plan and apply cleanly, then fail inside
  # certbot on the first deploy: the policy would name a record that cannot
  # exist in the zone it is scoped to.
  validation {
    condition     = alltrue([for name in var.certificate_names : name == var.dns_zone || endswith(name, ".${var.dns_zone}")])
    error_message = "Every certificate_names entry must be dns_zone itself or a name under it."
  }
}
