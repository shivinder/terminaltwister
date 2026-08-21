terraform {
  required_version = ">= 1.15" # 1.10+ is the hard floor (use_lockfile); tracking latest

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # State in the manually-created terminaltwister-tfstate bucket
  # (S3-native locking — no DynamoDB table needed).
  backend "s3" {
    bucket       = "terminaltwister-tfstate"
    key          = "production/terraform.tfstate"
    region       = "ap-southeast-2"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  # Safety net, not the primary mechanism: the wordpress module tags its own
  # resources via local.common_tags. This catches anything added later that
  # forgets to, so nothing lands in the account unattributed. Environment is
  # not repeated here — it lives in the module, where it can't drift from the
  # environment argument.
  default_tags {
    tags = {
      Project   = "terminaltwister"
      ManagedBy = "terraform"
    }
  }
}
