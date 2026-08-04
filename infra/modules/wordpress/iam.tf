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
# list the bucket — nothing else
data "aws_iam_policy_document" "backup" {
  statement {
    sid       = "ReadWriteBackups"
    actions   = ["s3:PutObject", "s3:GetObject"]
    resources = ["${aws_s3_bucket.backups.arn}/*"]
  }

  statement {
    sid       = "ListBackupBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.backups.arn]
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
}
