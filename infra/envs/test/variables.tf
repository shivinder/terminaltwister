variable "aws_region" {
  type    = string
  default = "ap-southeast-2" # Sydney
}

variable "key_name" {
  description = "Existing EC2 key pair name (not the .pem filename)"
  type        = string
  default     = "kp-sydney-01"
}

# Empty by default: test is disposable, and nobody wants a 3am email about it.
# Set TF_VAR_alarm_email here too if you want to rehearse the alerting path.
variable "alarm_email" {
  description = "Where backup-failure alerts are emailed. Empty disables alerting."
  type        = string
  default     = ""
}
