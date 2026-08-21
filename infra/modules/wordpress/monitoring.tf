# --- Backup failure alerting ---
#
# The nightly backup script (ansible/roles/ops/templates/wp-backup.sh.j2)
# publishes BackupSuccess=1 after a good run and 0 from its failure trap.
# Nothing watched that metric, so a failed backup only ever reached a log file
# on the instance — and a terminated instance publishes nothing at all.
#
# All of this is skipped when alarm_email is empty (the default), so an
# environment that doesn't want alerting creates no resources and costs nothing.

locals {
  alerts_enabled = var.alarm_email != "" ? 1 : 0
}

resource "aws_sns_topic" "alerts" {
  count = local.alerts_enabled
  name  = "${local.name}-alerts"

  # Deliberately unencrypted. CloudWatch cannot publish through the AWS-managed
  # SNS key (alias/aws/sns) — delivery would fail silently, which is the exact
  # failure this whole file exists to prevent — and a customer-managed key would
  # cost more per month than everything else here combined. The messages carry
  # alarm names and timestamps, not secrets.

  tags = local.common_tags
}

# AWS emails a confirmation link to var.alarm_email; the subscription sits in
# PendingConfirmation until a human clicks it. Terraform cannot perform that
# step, and an unconfirmed subscription is indistinguishable from a working one
# until the first alarm goes unanswered — so it is called out in the README's
# "After apply" section rather than left to be discovered.
resource "aws_sns_topic_subscription" "alerts_email" {
  count     = local.alerts_enabled
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_metric_alarm" "backup_failed" {
  count      = local.alerts_enabled
  alarm_name = "${local.name}-backup-failed"

  alarm_description = join(" ", [
    "No successful WordPress backup in the last 24 hours (${var.environment}).",
    "Either the nightly run failed, or it never happened — instance down,",
    "cron broken, or disk full. Check /var/log/wp-backup.log on the instance.",
  ])

  # Project-scoped, not "WordPress/": a second WordPress install in this account
  # would otherwise publish into the same namespace, and only the Environment
  # dimension would separate them — two projects each with a "production" would
  # collide on one metric.
  namespace   = "TerminalTwister/Backups"
  metric_name = "BackupSuccess"
  dimensions  = { Environment = var.environment }

  # One datapoint per day — cron runs the backup at 03:00 (backup_cron_hour in
  # ansible/group_vars/all/main.yml). Minimum over the period means a single 0
  # wins over any number of 1s, so a retry can't mask a failure.
  statistic          = "Minimum"
  period             = 86400
  evaluation_periods = 1

  threshold           = 1
  comparison_operator = "LessThanThreshold"

  # The line that makes this alarm worth having. Treating absent data as a
  # breach turns "the backup reported a failure" into "the backup did not report
  # success", which also covers a terminated instance, a broken cron and a full
  # disk — none of which the script is alive to report on.
  #
  # Consequence: this alarm fires once shortly after a first apply, because no
  # backup has run yet. That is a free end-to-end test of metric -> alarm -> SNS
  # -> inbox, and it clears itself after the first successful 03:00 run.
  treat_missing_data = "breaching"

  alarm_actions = [aws_sns_topic.alerts[0].arn]

  # Without this you hear about the breakage and never hear about the recovery.
  ok_actions = [aws_sns_topic.alerts[0].arn]

  tags = local.common_tags
}
