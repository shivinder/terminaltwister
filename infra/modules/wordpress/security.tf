resource "aws_security_group" "wordpress" {
  # name_prefix rather than name, paired with create_before_destroy below.
  #
  # The SG name is ForceNew, so anything that renames it — a local.name change,
  # a new environment — plans a replacement. Destroy-then-create is the default
  # order, and AWS refuses to delete a group the instance's ENI still references
  # (DependencyViolation), so such an apply dies halfway. Creating the
  # replacement first and swapping the instance onto it removes the window.
  #
  # The suffix AWS appends is invisible to the deploy job: .gitlab-ci.yml finds
  # this group by its Name TAG (tt-wp-<env>-sg), set below and unchanged.
  name_prefix = "${local.name}-sg-"
  description = "WordPress ${var.environment}: web from allowed CIDRs, DB inside SG only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_web_cidrs
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_web_cidrs
  }

  # SSH stays closed unless admin_ssh_cidrs is set —
  # the CI deploy job adds/revokes the runner IP per run.
  dynamic "ingress" {
    for_each = length(var.admin_ssh_cidrs) > 0 ? [1] : []
    content {
      description = "Admin SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.admin_ssh_cidrs
    }
  }

  # MariaDB reachable only from members of this SG (over private IPs).
  # Today that's the WordPress instance talking to itself; later, a
  # dedicated DB instance in the private subnet joins the same SG
  # and nothing else needs to change.
  ingress {
    description = "MariaDB within SG"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, { Name = "${local.name}-sg" })
}
