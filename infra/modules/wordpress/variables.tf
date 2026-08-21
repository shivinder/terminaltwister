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
