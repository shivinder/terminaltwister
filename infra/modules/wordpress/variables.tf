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
