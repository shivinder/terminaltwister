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

# --- Certificate issuance (DNS-01) ---
#
# certbot on the instance proves control of each name to Let's Encrypt by
# publishing a TXT record at _acme-challenge.<name>, so the instance role has to
# write to the zone. That zone is shared: it holds the other environment's names
# and the mail records. The conditions are what keep this from being "edit the
# zone" — the role can touch its own challenge records, as TXT, and nothing else.
#
# The name scoping is also what keeps the environments apart. Whoever can write
# _acme-challenge.<name> can obtain a certificate for <name>, so test is given
# its own name and never production's.
data "aws_iam_policy_document" "acme_dns" {
  count = length(var.certificate_names) > 0 ? 1 : 0

  statement {
    sid       = "WriteAcmeChallengeRecords"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = [data.aws_route53_zone.this[0].arn]

    # ForAllValues: one request can carry several changes, and every one of
    # them has to pass. Route53 compares names lower-cased, without the
    # trailing dot.
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "route53:ChangeResourceRecordSetsNormalizedRecordNames"
      values   = [for name in var.certificate_names : "_acme-challenge.${lower(name)}"]
    }

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "route53:ChangeResourceRecordSetsRecordTypes"
      values   = ["TXT"]
    }

    # certbot upserts the record, then deletes it once the order is validated
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "route53:ChangeResourceRecordSetsActions"
      values   = ["UPSERT", "DELETE"]
    }
  }

  # How certbot finds the zone for a name, and how it waits for the record to
  # reach Route53's nameservers before asking Let's Encrypt to look. Neither
  # can be scoped to one zone; both are read-only.
  statement {
    sid       = "FindZoneAndAwaitChange"
    actions   = ["route53:ListHostedZones", "route53:GetChange"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "acme_dns" {
  count  = length(var.certificate_names) > 0 ? 1 : 0
  name   = "${local.name}-acme-dns"
  role   = aws_iam_role.wordpress.id
  policy = data.aws_iam_policy_document.acme_dns[0].json
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
