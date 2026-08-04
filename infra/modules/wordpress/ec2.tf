# Latest Ubuntu 26.04 LTS ("Resolute Raccoon") arm64 AMI (Graviton),
# via Canonical's public SSM parameter
data "aws_ssm_parameter" "ubuntu_2604_ami" {
  name = "/aws/service/canonical/ubuntu/server/26.04/stable/current/arm64/hvm/ebs-gp3/ami-id"
}

resource "aws_instance" "wordpress" {
  ami                    = nonsensitive(data.aws_ssm_parameter.ubuntu_2604_ami.value)
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.wordpress.id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.wordpress.name

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only
  }

  lifecycle {
    # Don't replace the instance every time Canonical publishes a new AMI
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
