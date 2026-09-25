# Multi-AZ network: public subnets (ALB + NAT), private web and app subnets
# (egress through NAT), and isolated database subnets (no internet route).
#
# By default it creates its own VPC. When existing_vpc_id is set (for example
# because the account has reached its VPC quota), it builds the same subnets,
# NAT gateway, route tables and flow logs inside that VPC instead and reuses
# its internet gateway. The existing VPC, its internet gateway, its default
# security group and its other subnets are never modified or deleted.

data "aws_availability_zones" "available" {
  #checkov:skip=CKV_AWS_394:Subnets use a fixed slice of the zone list (one per subnet CIDR), so a new AWS zone never changes the layout; excluded_zone_ids pins out unsupported zones.
  state            = "available"
  exclude_zone_ids = var.excluded_zone_ids
}

locals {
  azs        = slice(data.aws_availability_zones.available.names, 0, length(var.public_subnet_cidrs))
  nat_count  = var.single_nat_gateway ? 1 : length(local.azs)
  create_vpc = var.existing_vpc_id == ""

  vpc_id              = local.create_vpc ? aws_vpc.this[0].id : data.aws_vpc.existing[0].id
  vpc_cidr_block      = local.create_vpc ? aws_vpc.this[0].cidr_block : data.aws_vpc.existing[0].cidr_block
  internet_gateway_id = local.create_vpc ? aws_internet_gateway.this[0].id : data.aws_internet_gateway.existing[0].internet_gateway_id
}

resource "aws_vpc" "this" {
  count                = local.create_vpc ? 1 : 0
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.name }
}

data "aws_vpc" "existing" {
  count = local.create_vpc ? 0 : 1
  id    = var.existing_vpc_id
}

# Lock down the default security group so nothing can use it by accident.
# Only in a VPC this module owns: in a shared VPC other workloads may rely on it.
resource "aws_default_security_group" "default" {
  count  = local.create_vpc ? 1 : 0
  vpc_id = aws_vpc.this[0].id
  tags   = { Name = "${var.name}-default-deny" }
}

moved {
  from = aws_vpc.this
  to   = aws_vpc.this[0]
}

moved {
  from = aws_default_security_group.default
  to   = aws_default_security_group.default[0]
}

# ---------------------------------------------------------------------------
# Subnets
# ---------------------------------------------------------------------------

resource "aws_subnet" "public" {
  count                   = length(local.azs)
  vpc_id                  = local.vpc_id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = { Name = "${var.name}-public-${local.azs[count.index]}", Tier = "public" }
}

resource "aws_subnet" "web" {
  count             = length(local.azs)
  vpc_id            = local.vpc_id
  cidr_block        = var.web_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = { Name = "${var.name}-web-${local.azs[count.index]}", Tier = "web" }
}

resource "aws_subnet" "app" {
  count             = length(local.azs)
  vpc_id            = local.vpc_id
  cidr_block        = var.app_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = { Name = "${var.name}-app-${local.azs[count.index]}", Tier = "app" }
}

resource "aws_subnet" "db" {
  count             = length(local.azs)
  vpc_id            = local.vpc_id
  cidr_block        = var.db_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = { Name = "${var.name}-db-${local.azs[count.index]}", Tier = "db" }
}

# ---------------------------------------------------------------------------
# Internet and NAT gateways
# ---------------------------------------------------------------------------

resource "aws_internet_gateway" "this" {
  count  = local.create_vpc ? 1 : 0
  vpc_id = aws_vpc.this[0].id
  tags   = { Name = var.name }
}

moved {
  from = aws_internet_gateway.this
  to   = aws_internet_gateway.this[0]
}

# An existing VPC must already have an internet gateway (the default VPC does).
data "aws_internet_gateway" "existing" {
  count = local.create_vpc ? 0 : 1
  filter {
    name   = "attachment.vpc-id"
    values = [var.existing_vpc_id]
  }
}

resource "aws_eip" "nat" {
  count  = local.nat_count
  domain = "vpc"
  tags   = { Name = "${var.name}-nat-${count.index}" }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count         = local.nat_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = { Name = "${var.name}-nat-${local.azs[count.index]}" }
}

# ---------------------------------------------------------------------------
# Routing
# ---------------------------------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = local.vpc_id
  tags   = { Name = "${var.name}-public" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = local.internet_gateway_id
}

resource "aws_route_table_association" "public" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# One private route table per AZ so each AZ uses its own NAT gateway when
# single_nat_gateway = false (no cross-AZ dependency).
resource "aws_route_table" "private" {
  count  = length(local.azs)
  vpc_id = local.vpc_id
  tags   = { Name = "${var.name}-private-${local.azs[count.index]}" }
}

resource "aws_route" "private_nat" {
  count                  = length(local.azs)
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.single_nat_gateway ? 0 : count.index].id
}

resource "aws_route_table_association" "web" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.web[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_route_table_association" "app" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Database subnets get a route table with only the local VPC route.
resource "aws_route_table" "db" {
  vpc_id = local.vpc_id
  tags   = { Name = "${var.name}-db-isolated" }
}

resource "aws_route_table_association" "db" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.db[count.index].id
  route_table_id = aws_route_table.db.id
}

# ---------------------------------------------------------------------------
# VPC flow logs (encrypted, retained)
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "flow_logs" {
  #checkov:skip=CKV_AWS_338:Retention is a per-environment decision set through flow_log_retention_days (365 days in prod).
  name              = "/${var.name}/vpc-flow-logs"
  retention_in_days = var.flow_log_retention_days
  kms_key_id        = var.kms_key_arn
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "${var.iam_name}-vpc-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json
}

data "aws_iam_policy_document" "flow_logs" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = [
      aws_cloudwatch_log_group.flow_logs.arn,
      "${aws_cloudwatch_log_group.flow_logs.arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "vpc-flow-logs"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs.json
}

# Whole-VPC flow log when this module owns the VPC.
resource "aws_flow_log" "this" {
  count                = local.create_vpc ? 1 : 0
  vpc_id               = aws_vpc.this[0].id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn         = aws_iam_role.flow_logs.arn
}

moved {
  from = aws_flow_log.this
  to   = aws_flow_log.this[0]
}

# In a shared VPC, log only this stack's subnets, not other workloads' traffic.
resource "aws_flow_log" "subnets" {
  count                = local.create_vpc ? 0 : length(local.azs) * 4
  subnet_id            = concat(aws_subnet.public[*].id, aws_subnet.web[*].id, aws_subnet.app[*].id, aws_subnet.db[*].id)[count.index]
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn         = aws_iam_role.flow_logs.arn
}
