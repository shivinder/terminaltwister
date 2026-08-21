locals {
  # Prefix every AWS name and Name tag so this project's resources are
  # distinguishable from anything else in the account — IAM especially,
  # where the console lists every role in one flat, region-less view.
  # Buckets deliberately keep the longer terminaltwister-* form: S3 names
  # are globally unique and a two-letter prefix collides with the world.
  name = "tt-wp-${var.environment}"

  common_tags = {
    Project     = "terminaltwister"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Exists only to validate var.availability_zone — nothing selects from it. The
# opt-in-status filter is the part that matters: it excludes Local Zones and
# opt-in regions, and an opted-in Local Zone reports state "available" exactly
# like a standard AZ, so `state` alone never distinguished them.
data "aws_availability_zones" "real" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# --- VPC ---

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, { Name = "${local.name}-vpc" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.common_tags, { Name = "${local.name}-igw" })
}

# --- VPC defaults ---
#
# Creating a VPC also creates a default security group, route table and NACL.
# Terraform doesn't manage them unless asked, so they would sit in the console
# unnamed and unprefixed. Adopt the two that can be adopted safely.

# An empty aws_default_security_group means no ingress and no egress: nothing
# should ever use this SG, and now nothing can. AWS won't let the default SG
# be renamed (its name is always "default"), so the Name tag is what shows.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, { Name = "${local.name}-default-sg-unused" })
}

# The VPC's main route table, which aws_subnet.private inherits for want of an
# association of its own. No route blocks = local traffic only, which is what
# a private subnet with no NAT gateway should have. Adopting it puts that in
# version control instead of leaving it to the default.
resource "aws_default_route_table" "default" {
  default_route_table_id = aws_vpc.this.default_route_table_id

  tags = merge(local.common_tags, { Name = "${local.name}-private-rt" })
}

# The default NACL is deliberately NOT adopted: aws_default_network_acl with
# no rules denies all traffic, and every subnet here uses it. Naming it is not
# worth an outage.

# --- Subnets ---
#
# Both subnets sit in one AZ deliberately: one instance, and an EBS volume that
# can only ever attach within its own zone.
#
# The zone is pinned, not read from aws_availability_zones. That data source
# returns every zone the account is opted into, sorted by name — and this account
# is opted into the Perth Local Zone, whose name (ap-southeast-2-per-1a) sorts
# ahead of ap-southeast-2a. names[0] therefore resolved to Perth: 13 instance
# types, all x86, no Graviton at all, and its own EIP border group. Nothing
# looked wrong, because a Local Zone belongs to its parent region and every
# string in this config still said ap-southeast-2.
#
# Pinning also stops an impaired zone reshuffling the list. availability_zone is
# ForceNew on a subnet and subnet_id is ForceNew on the instance, so a plan run
# during a zone incident would otherwise propose destroying the instance and its
# root volume along with it.

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  # Guards the pin. A typo, a zone from another region, or any Local Zone the
  # account opts into later fails here at plan time — rather than part-way
  # through an apply, at aws_instance, with an unsupported-instance-type error
  # that points at instance_type instead of at the zone.
  lifecycle {
    precondition {
      condition     = contains(data.aws_availability_zones.real.names, var.availability_zone)
      error_message = "availability_zone must be a standard AZ in this region, not a Local Zone. Available: ${join(", ", data.aws_availability_zones.real.names)}."
    }
  }

  tags = merge(local.common_tags, { Name = "${local.name}-public" })
}

# Reserved for a future dedicated database instance. Not used yet
# (the DB currently runs on the WordPress EC2), so no NAT gateway
# is created — add one when this subnet gets its first instance.
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone

  tags = merge(local.common_tags, { Name = "${local.name}-private" })
}

# --- Routing (public only for now) ---

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.common_tags, { Name = "${local.name}-public-rt" })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
