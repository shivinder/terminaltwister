data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "wordpress" {
  name               = "${local.name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
  tags               = local.common_tags
}

# Least privilege: write backups, read them back for restores (wp-restore.sh),
# clean up after a failed upload, list the bucket — nothing else
data "aws_iam_policy_document" "backup" {
  statement {
    sid = "ReadWriteBackups"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      # `aws s3 cp` switches to multipart above 8 MB, which wp-content
      # tarballs exceed. Without Abort the CLI cannot tidy up when an
      # upload dies mid-flight: the uploaded parts stay billable and are
      # invisible to `aws s3 ls`. s3.tf sweeps up whatever escapes this.
      "s3:AbortMultipartUpload",
    ]

    resources = ["${aws_s3_bucket.backups.arn}/*"]
  }

  statement {
    sid       = "ListBackupBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.backups.arn]
  }

  # Lets wp-backup.sh report whether it worked. Granted unconditionally rather
  # than behind enable_cloudwatch: gating it is what made backup failures silent
  # in the first place, and one custom metric is inside the CloudWatch free tier.
  # monitoring.tf alarms on the result.
  statement {
    sid     = "PublishBackupMetric"
    actions = ["cloudwatch:PutMetricData"]

    # PutMetricData has no resource-level permissions; the namespace condition
    # is the only way to scope it, and is what keeps this from being cloudwatch:*
    resources = ["*"]

    condition {
      test     = "StringLike"
      variable = "cloudwatch:namespace"
      values   = ["TerminalTwister/*"]
    }
  }
}

resource "aws_iam_role_policy" "backup" {
  name   = "${local.name}-backup"
  role   = aws_iam_role.wordpress.id
  policy = data.aws_iam_policy_document.backup.json
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  count      = var.enable_cloudwatch ? 1 : 0
  role       = aws_iam_role.wordpress.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "wordpress" {
  name = "${local.name}-profile"
  role = aws_iam_role.wordpress.name
  tags = local.common_tags
}
