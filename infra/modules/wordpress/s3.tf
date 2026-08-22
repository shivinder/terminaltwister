resource "aws_s3_bucket" "backups" {
  bucket = var.backup_bucket_name
  tags   = merge(local.common_tags, { Name = var.backup_bucket_name })
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# AWS applies SSE-S3 to new buckets by default, but these objects are database
# dumps — state it explicitly so the setting is version-controlled and any
# drift shows up in a plan.
resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

# SSE above covers these objects at rest; this covers them in transit. S3 accepts
# plain HTTP unless a policy says otherwise, and this bucket holds the database
# password, the WordPress salts and the Let's Encrypt private keys — see "What the
# backup bucket holds" in infra/README.md.
#
# Nothing legitimate is affected: the AWS CLI on the instance and Terraform's own
# S3 backend both speak HTTPS already, so this only ever denies something that
# should not have been happening.
data "aws_iam_policy_document" "backups_tls_only" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    # Both ARNs on purpose. The bucket ARN alone would leave ListBucket reachable
    # over HTTP; the /* form alone would leave the object operations covered but
    # not the bucket ones.
    resources = [
      aws_s3_bucket.backups.arn,
      "${aws_s3_bucket.backups.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "backups" {
  bucket = aws_s3_bucket.backups.id
  policy = data.aws_iam_policy_document.backups_tls_only.json

  # block_public_policy rejects a policy that GRANTS public access. This one only
  # denies, so it is accepted either way — the dependency is here to keep the two
  # bucket-level writes ordered rather than racing on a freshly created bucket.
  depends_on = [aws_s3_bucket_public_access_block.backups]
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "expire-old-backups"
    status = "Enabled"

    filter {}

    expiration {
      days = var.backup_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    # Backstop for the multipart uploads iam.tf grants Abort on: if the
    # instance is terminated or the process killed mid-upload, the CLI never
    # gets to abort and the parts linger, billed but unlisted. S3 discards
    # them a week after the upload started.
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # A second rule, not another clause in the one above: S3 rejects
  # expired_object_delete_marker in the same rule as expiration.days.
  #
  # On a versioned bucket, expiring the current version does not delete anything
  # — it writes a delete marker and pushes the version noncurrent.
  # noncurrent_version_expiration then clears the version it displaced, leaving a
  # zero-byte marker with nothing behind it and no rule that removes it. Three
  # archives a night is roughly 1,100 of those a year, each one slowing every
  # ListObjectVersions call, including the ones wp-restore.sh makes.
  rule {
    id     = "expire-delete-markers"
    status = "Enabled"

    filter {}

    expiration {
      expired_object_delete_marker = true
    }
  }
}
