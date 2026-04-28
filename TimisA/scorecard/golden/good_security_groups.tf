# GOLDEN: Security groups with least-privilege ingress rules.
# Good: restricted CIDR, named ports only, egress explicit.

resource "aws_security_group" "alb" {
  name        = "contoso-alb-sg"
  description = "ALB: HTTPS only"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name        = "contoso-alb-sg"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_security_group" "webapp" {
  name        = "contoso-webapp-sg"
  description = "ECS tasks: only from ALB"
  vpc_id      = var.vpc_id

  ingress {
    description     = "App port from ALB only"
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name        = "contoso-webapp-sg"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
