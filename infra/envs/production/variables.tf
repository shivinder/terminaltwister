variable "aws_region" {
  type    = string
  default = "ap-southeast-2" # Sydney
}

variable "key_name" {
  description = "Existing EC2 key pair name (not the .pem filename)"
  type        = string
  default     = "kp-sydney-01"
}

# Set via TF_VAR_alarm_email in GitLab CI. Left empty, production applies with
# no backup alerting at all — `terraform output backup_alerts` says so.
variable "alarm_email" {
  description = "Where backup-failure alerts are emailed. Empty disables alerting."
  type        = string
  default     = ""
}
