# ECS Fargate + ALB + CloudFront (ADR-0006)

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  name       = "contoso-webapp-${var.environment}"
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

# ── ECR Repository ────────────────────────────────────────────────────────────

resource "aws_ecr_repository" "webapp" {
  name                 = "contoso/webapp"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "KMS" }

  tags = { Name = "contoso-webapp" }
}

# ── ECS Cluster ───────────────────────────────────────────────────────────────

resource "aws_ecs_cluster" "main" {
  name = "${local.name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# ── IAM Task Role (least-privilege — only what webapp needs) ──────────────────

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task" {
  name               = "${local.name}-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy" "task" {
  name = "webapp-task-policy"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3: write reports only to webapp bucket (ADR-0002 — no cross-bucket access)
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject"]
        Resource = "${var.reports_bucket_arn}/*"
      },
      # Secrets Manager: read DB credentials (ADR-0003)
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = var.db_secret_arn
      }
    ]
  })
}

resource "aws_iam_role" "task_execution" {
  name               = "${local.name}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ── CloudWatch Log Group ──────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "webapp" {
  name              = "/ecs/${local.name}"
  retention_in_days = 30
}

# ── ECS Task Definition ───────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "webapp" {
  family                   = local.name
  cpu                      = 512
  memory                   = 1024
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = "webapp"
    image     = "${aws_ecr_repository.webapp.repository_url}:latest"
    essential = true

    portMappings = [{ containerPort = 5000, protocol = "tcp" }]

    environment = [
      { name = "ENV",        value = var.environment },
      { name = "DB_HOST",    value = var.db_proxy_endpoint },
      { name = "DB_PORT",    value = "5432" },
      { name = "DB_NAME",    value = "contoso" },
      { name = "REDIS_URL",  value = "rediss://${var.redis_endpoint}:6379/0" },
      { name = "S3_BUCKET",  value = var.reports_bucket_name },
    ]

    # DB credentials injected from Secrets Manager — never in plaintext (ADR-0003)
    secrets = [
      { name = "DB_USER",     valueFrom = "${var.db_secret_arn}:username::" },
      { name = "DB_PASSWORD", valueFrom = "${var.db_secret_arn}:password::" },
    ]

    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:5000/health || exit 1"]
      interval    = 10
      timeout     = 5
      retries     = 3
      startPeriod = 15
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.webapp.name
        "awslogs-region"        = local.region
        "awslogs-stream-prefix" = "webapp"
      }
    }
  }])
}

# Warmup task definition (ADR-0005 — decoupled from batch cron)
resource "aws_ecs_task_definition" "warmup" {
  family                   = "${local.name}-warmup"
  cpu                      = 256
  memory                   = 512
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = "warmup"
    image     = "${aws_ecr_repository.webapp.repository_url}:latest"
    essential = true
    command   = ["python", "-c", "from app import warmup_cache; warmup_cache()"]

    environment = [
      { name = "ENV",       value = var.environment },
      { name = "REDIS_URL", value = "rediss://${var.redis_endpoint}:6379/0" },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.webapp.name
        "awslogs-region"        = local.region
        "awslogs-stream-prefix" = "warmup"
      }
    }
  }])
}

# ── ALB ───────────────────────────────────────────────────────────────────────

resource "aws_lb" "webapp" {
  name               = "${local.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.sg_alb_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = var.environment == "prod" ? true : false
}

resource "aws_lb_target_group" "webapp" {
  name        = "${local.name}-tg"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# HTTPS listener — only created when a valid ACM certificate ARN is provided
resource "aws_lb_listener" "https" {
  count = var.acm_certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.webapp.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.webapp.arn
  }
}

# HTTP: redirect to HTTPS if cert is available, otherwise forward directly
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.webapp.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = var.acm_certificate_arn != "" ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = var.acm_certificate_arn == "" ? [1] : []
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.webapp.arn
    }
  }
}

# ── ECS Service with Auto-scaling ─────────────────────────────────────────────

resource "aws_ecs_service" "webapp" {
  name            = local.name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.webapp.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.sg_webapp_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.webapp.arn
    container_name   = "webapp"
    container_port   = 5000
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  lifecycle { ignore_changes = [desired_count] }
}

resource "aws_appautoscaling_target" "webapp" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.webapp.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = 2
  max_capacity       = 6
}

# Scale on CPU 60% (ADR-0006)
resource "aws_appautoscaling_policy" "webapp_cpu" {
  name               = "${local.name}-cpu-scaling"
  service_namespace  = aws_appautoscaling_target.webapp.service_namespace
  resource_id        = aws_appautoscaling_target.webapp.resource_id
  scalable_dimension = aws_appautoscaling_target.webapp.scalable_dimension
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 60.0
  }
}

# ── CloudFront ────────────────────────────────────────────────────────────────

resource "aws_cloudfront_distribution" "webapp" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "Contoso webapp — ${var.environment}"

  origin {
    domain_name = aws_lb.webapp.dns_name
    origin_id   = "alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Host"]
      cookies { forward = "all" }
    }
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
