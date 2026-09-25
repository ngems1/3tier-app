# Security groups chained tier by tier. Only the public ALB accepts traffic
# from the internet; every other tier accepts traffic only from the tier in
# front of it. There is no SSH anywhere: operators use SSM Session Manager.

resource "aws_security_group" "alb_public" {
  #checkov:skip=CKV2_AWS_5:Attached to the public ALB in the alb module; Checkov cannot follow the cross-module reference.
  name        = "${var.name}-alb-public"
  description = "Public web ALB: HTTPS (and HTTP for redirect) from the internet"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-alb-public" }
}

resource "aws_security_group" "web" {
  #checkov:skip=CKV2_AWS_5:Attached to the web launch template in the compute module.
  name        = "${var.name}-web"
  description = "Web tier instances (Nginx): HTTP from the public ALB only"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-web" }
}

resource "aws_security_group" "app_alb" {
  #checkov:skip=CKV2_AWS_5:Attached to the internal app ALB in the alb module.
  name        = "${var.name}-app-alb"
  description = "Internal app ALB: HTTP from the web tier only"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-app-alb" }
}

resource "aws_security_group" "app" {
  #checkov:skip=CKV2_AWS_5:Attached to the app launch template in the compute module.
  name        = "${var.name}-app"
  description = "App tier instances (FastAPI): API port from the internal ALB only"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-app" }
}

resource "aws_security_group" "db" {
  #checkov:skip=CKV2_AWS_5:Attached to the RDS instance in the database module.
  name        = "${var.name}-db"
  description = "RDS MySQL: port 3306 from the app tier only"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-db" }
}

# --- Public ALB --------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb_public.id
  description       = "HTTPS from the internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "alb_http_redirect" {
  #checkov:skip=CKV_AWS_260:Port 80 only serves a permanent redirect to HTTPS on the listener; no content is served over HTTP.
  security_group_id = aws_security_group.alb_public.id
  description       = "HTTP from the internet (redirected to HTTPS)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_to_web" {
  security_group_id            = aws_security_group.alb_public.id
  description                  = "Forward to web tier"
  referenced_security_group_id = aws_security_group.web.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

# --- Web tier ----------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "web_from_alb" {
  #checkov:skip=CKV_AWS_260:The source is the public ALB security group, not 0.0.0.0/0; web instances are never reachable from the internet directly.
  security_group_id            = aws_security_group.web.id
  description                  = "HTTP from the public ALB"
  referenced_security_group_id = aws_security_group.alb_public.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

resource "aws_vpc_security_group_egress_rule" "web_to_app_alb" {
  security_group_id            = aws_security_group.web.id
  description                  = "Proxy /api to the internal app ALB"
  referenced_security_group_id = aws_security_group.app_alb.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

resource "aws_vpc_security_group_egress_rule" "web_https_out" {
  security_group_id = aws_security_group.web.id
  description       = "HTTPS to AWS APIs (SSM, CloudWatch) through the NAT gateway"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# --- Internal app ALB --------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "app_alb_from_web" {
  #checkov:skip=CKV_AWS_260:The source is the web tier security group, not 0.0.0.0/0; this internal ALB is never reachable from the internet.
  security_group_id            = aws_security_group.app_alb.id
  description                  = "HTTP from the web tier"
  referenced_security_group_id = aws_security_group.web.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

resource "aws_vpc_security_group_egress_rule" "app_alb_to_app" {
  security_group_id            = aws_security_group.app_alb.id
  description                  = "Forward to app tier"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
}

# --- App tier ----------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "API traffic from the internal ALB"
  referenced_security_group_id = aws_security_group.app_alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
}

resource "aws_vpc_security_group_egress_rule" "app_to_db" {
  security_group_id            = aws_security_group.app.id
  description                  = "MySQL to RDS"
  referenced_security_group_id = aws_security_group.db.id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
}

resource "aws_vpc_security_group_egress_rule" "app_https_out" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS to AWS APIs (Secrets Manager, SSM, CloudWatch) through the NAT gateway"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# --- Database ----------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "MySQL from the app tier"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
}
