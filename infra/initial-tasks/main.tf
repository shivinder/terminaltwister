# Bootstrap — run ONCE, locally, before anything else.
#
# Creates the S3 bucket that all other Terraform configurations use as
# their state backend. Chicken-and-egg: this configuration cannot store
# its own state in the bucket it creates, so it uses LOCAL state
# (terraform.tfstate in this directory — see README.md).
#
#   cd infra/initial-tasks
#   terraform init
#   terraform apply

terraform {
  required_version = ">= 1.15"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "ap-southeast-2" # Sydney
}

variable "state_bucket_name" {
  type    = string
  default = "terminaltwister-tfstate"
}

provider "aws" {
  region = var.aws_region
}

resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket_name

  # Refuse `terraform destroy` — losing this bucket means losing all
  # environment state. Flip only if you truly mean to tear it down.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Project   = "terminaltwister"
    Purpose   = "terraform-state"
    ManagedBy = "terraform-bootstrap"
  }
}

# Versioning: every state change is recoverable
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Keep old state versions 90 days, then expire — bounds storage cost
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-noncurrent-state"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

output "state_bucket" {
  value = aws_s3_bucket.tfstate.bucket
}
