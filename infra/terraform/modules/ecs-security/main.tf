# Security groups for the ECS project. Only the public ALB accepts internet
# traffic; each task group accepts traffic only from the ALB, and the
# database only from the backend tasks.

resource "aws_security_group" "alb" {
  #checkov:skip=CKV2_AWS_5:Attached to the public ALB in the ecs-alb module; Checkov cannot follow the cross-module reference.
  name        = "${var.name}-alb"
  description = "Public ALB: HTTPS (and HTTP) from the internet"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-alb" }
}

resource "aws_security_group" "frontend" {
  #checkov:skip=CKV2_AWS_5:Attached to the frontend ECS service in the ecs module.
  name        = "${var.name}-frontend"
  description = "Frontend tasks (Nginx): HTTP from the ALB only"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-frontend" }
}

resource "aws_security_group" "backend" {
  #checkov:skip=CKV2_AWS_5:Attached to the backend ECS service in the ecs module.
  name        = "${var.name}-backend"
  description = "Backend tasks (FastAPI): API port from the ALB only"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-backend" }
}

resource "aws_security_group" "db" {
  #checkov:skip=CKV2_AWS_5:Attached to the RDS instance in the database module.
  name        = "${var.name}-db"
  description = "RDS MySQL: port 3306 from the backend tasks only"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-db" }
}

# --- ALB ---------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from the internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  #checkov:skip=CKV_AWS_260:Port 80 redirects to HTTPS once a domain is configured (temporary HTTP-only mode before that).
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from the internet (redirected to HTTPS when a domain is set)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_to_frontend" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward to frontend tasks"
  referenced_security_group_id = aws_security_group.frontend.id
  ip_protocol                  = "tcp"
  from_port                    = var.frontend_port
  to_port                      = var.frontend_port
}

resource "aws_vpc_security_group_egress_rule" "alb_to_backend" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward /api to backend tasks"
  referenced_security_group_id = aws_security_group.backend.id
  ip_protocol                  = "tcp"
  from_port                    = var.backend_port
  to_port                      = var.backend_port
}

# --- Frontend tasks ------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "frontend_from_alb" {
  security_group_id            = aws_security_group.frontend.id
  description                  = "HTTP from the ALB"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.frontend_port
  to_port                      = var.frontend_port
}

resource "aws_vpc_security_group_egress_rule" "frontend_https_out" {
  security_group_id = aws_security_group.frontend.id
  description       = "HTTPS to ECR and CloudWatch Logs through the NAT gateway"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# --- Backend tasks -------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "backend_from_alb" {
  security_group_id            = aws_security_group.backend.id
  description                  = "API traffic from the ALB"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.backend_port
  to_port                      = var.backend_port
}

resource "aws_vpc_security_group_egress_rule" "backend_to_db" {
  security_group_id            = aws_security_group.backend.id
  description                  = "MySQL to RDS"
  referenced_security_group_id = aws_security_group.db.id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
}

resource "aws_vpc_security_group_egress_rule" "backend_https_out" {
  security_group_id = aws_security_group.backend.id
  description       = "HTTPS to ECR, Secrets Manager and CloudWatch Logs through the NAT gateway"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# --- Database --------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "db_from_backend" {
  security_group_id            = aws_security_group.db.id
  description                  = "MySQL from the backend tasks"
  referenced_security_group_id = aws_security_group.backend.id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
}
