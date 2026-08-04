variable "aws_region" {
  type    = string
  default = "ap-southeast-2" # Sydney
}

variable "key_name" {
  description = "Existing EC2 key pair name (not the .pem filename)"
  type        = string
  default     = "kp-sydney-01"
}
