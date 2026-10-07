# Latest Debian 13 ("trixie") arm64 AMI (Graviton), via the public SSM
# parameter the Debian cloud team publishes from its own account
# (136693071363). The major version is pinned in the path on purpose:
# php_version in ansible/group_vars/all/main.yml follows what this release
# ships, so moving to Debian 14 is a change to both, not a surprise on rebuild.
# The image's login user is `admin`.
data "aws_ssm_parameter" "debian_ami" {
  name = "/aws/service/debian/release/13/latest/arm64"
}

resource "aws_instance" "wordpress" {
  ami                    = nonsensitive(data.aws_ssm_parameter.debian_ami.value)
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.wordpress.id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.wordpress.name

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true

    # Already the AWS default; stated so the choice is version-controlled and
    # any drift shows up in a plan, the same reasoning s3.tf uses for its
    # explicit SSE block. Safe because snapshots.tf keeps snapshots that outlive
    # the instance — and the alternative, false, leaves an orphaned volume
    # billing quietly after every termination.
    delete_on_termination = true

    # Without this the volume shows up untagged and unnamed in the EC2 Volumes
    # list, misses cost allocation by Project, and — since snapshots.tf targets
    # volumes by exactly these tags — would never be snapshotted.
    tags = merge(local.common_tags, { Name = "${local.name}-root" })
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only
  }

  lifecycle {
    # Don't replace the instance every time Debian publishes a new AMI
    ignore_changes = [ami]
  }

  tags = merge(local.common_tags, { Name = local.name })
}

resource "aws_eip" "wordpress" {
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${local.name}-eip" })
}

resource "aws_eip_association" "wordpress" {
  instance_id   = aws_instance.wordpress.id
  allocation_id = aws_eip.wordpress.id
}
