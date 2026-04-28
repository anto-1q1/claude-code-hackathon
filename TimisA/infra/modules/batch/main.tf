# AWS Batch + EventBridge (ADR-0006, ADR-0005)

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  name       = "contoso-batch-${var.environment}"
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

# ── ECR Repository ────────────────────────────────────────────────────────────

resource "aws_ecr_repository" "batch" {
  name                 = "contoso/batch"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "KMS" }
}

# ── IAM Role for Batch Jobs ───────────────────────────────────────────────────

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "batch_job" {
  name               = "${local.name}-job-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy" "batch_job" {
  name = "batch-job-policy"
  role = aws_iam_role.batch_job.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3: write to batch bucket only (ADR-0002 — no cross-bucket access)
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject"]
        Resource = "${var.output_bucket_arn}/*"
      },
      # Secrets Manager: read DB credentials (ADR-0003)
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = var.db_secret_arn
      },
      # SNS: publish completion/failure notifications
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.batch_notifications.arn
      }
    ]
  })
}

resource "aws_iam_role" "batch_execution" {
  name               = "${local.name}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "batch_execution" {
  role       = aws_iam_role.batch_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ── CloudWatch Log Group ──────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "batch" {
  name              = "/aws/batch/${local.name}"
  retention_in_days = 90
}

# ── SNS Topic for notifications ───────────────────────────────────────────────

resource "aws_sns_topic" "batch_notifications" {
  name = "${local.name}-notifications"
  tags = { Name = "${local.name}-notifications" }
}

# ── AWS Batch — Compute Environment (Fargate) ─────────────────────────────────

data "aws_iam_policy_document" "batch_service_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["batch.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "batch_service" {
  name               = "${local.name}-service-role"
  assume_role_policy = data.aws_iam_policy_document.batch_service_assume.json
}

resource "aws_iam_role_policy_attachment" "batch_service" {
  role       = aws_iam_role.batch_service.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole"
}

resource "aws_batch_compute_environment" "main" {
  compute_environment_name = "${local.name}-env"
  type                     = "MANAGED"
  service_role             = aws_iam_role.batch_service.arn

  compute_resources {
    type               = "FARGATE"
    max_vcpus          = 4
    subnets            = var.private_subnet_ids
    security_group_ids = [var.sg_batch_id]
  }
}

resource "aws_batch_job_queue" "main" {
  name     = "${local.name}-queue"
  state    = "ENABLED"
  priority = 1

  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.main.arn
  }
}

resource "aws_batch_job_definition" "reconciliation" {
  name = "${local.name}-reconciliation"
  type = "container"

  platform_capabilities = ["FARGATE"]

  # Idempotent — safe to retry (ADR-0008)
  retry_strategy {
    attempts = 2
    evaluate_on_exit {
      on_status_reason = "Host EC2*terminated"
      action           = "RETRY"
    }
    evaluate_on_exit {
      on_reason = "*"
      action    = "EXIT"
    }
  }

  # 4-hour timeout (CLAUDE.md batch rule)
  timeout { attempt_duration_seconds = 14400 }

  container_properties = jsonencode({
    image            = "${aws_ecr_repository.batch.repository_url}:latest"
    jobRoleArn       = aws_iam_role.batch_job.arn
    executionRoleArn = aws_iam_role.batch_execution.arn

    fargatePlatformConfiguration = { platformVersion = "LATEST" }
    networkConfiguration         = { assignPublicIp  = "DISABLED" }

    resourceRequirements = [
      { type = "VCPU",   value = "1" },
      { type = "MEMORY", value = "2048" }
    ]

    environment = [
      { name = "ENV",           value = var.environment },
      { name = "DB_HOST",       value = var.db_proxy_endpoint },
      { name = "DB_PORT",       value = "5432" },
      { name = "DB_NAME",       value = "contoso" },
      { name = "S3_BUCKET",     value = var.output_bucket_name },
      { name = "SNS_TOPIC_ARN", value = aws_sns_topic.batch_notifications.arn },
    ]

    # DB credentials from Secrets Manager — never in plaintext (ADR-0003)
    secrets = [
      { name = "DB_USER",     valueFrom = "${var.db_secret_arn}:username::" },
      { name = "DB_PASSWORD", valueFrom = "${var.db_secret_arn}:password::" },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.batch.name
        "awslogs-region"        = local.region
        "awslogs-stream-prefix" = "reconciliation"
      }
    }
  })
}

# ── EventBridge Rules (ADR-0005 — decouple batch/webapp dependency) ───────────

data "aws_iam_policy_document" "eventbridge_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eventbridge" {
  name               = "${local.name}-eventbridge-role"
  assume_role_policy = data.aws_iam_policy_document.eventbridge_assume.json
}

resource "aws_iam_role_policy" "eventbridge" {
  name = "eventbridge-policy"
  role = aws_iam_role.eventbridge.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["batch:SubmitJob"]
        Resource = [aws_batch_job_queue.main.arn, aws_batch_job_definition.reconciliation.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["ecs:RunTask"]
        Resource = var.webapp_warmup_arn
      },
      {
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = "*"
      }
    ]
  })
}

# 01:55 UTC — trigger webapp cache warmup (5 min before batch)
resource "aws_cloudwatch_event_rule" "warmup_trigger" {
  name                = "contoso-warmup-trigger-${var.environment}"
  description         = "Trigger webapp cache warmup 5 min before batch reconciliation"
  schedule_expression = "cron(55 1 * * ? *)"
}

resource "aws_cloudwatch_event_target" "warmup" {
  rule      = aws_cloudwatch_event_rule.warmup_trigger.name
  target_id = "WebappWarmupTask"
  arn       = var.webapp_cluster_arn
  role_arn  = aws_iam_role.eventbridge.arn

  ecs_target {
    task_definition_arn = var.webapp_warmup_arn
    launch_type         = "FARGATE"
    task_count          = 1

    network_configuration {
      subnets          = var.webapp_subnet_ids
      security_groups  = [var.webapp_sg_id]
      assign_public_ip = false
    }
  }
}

# 02:00 UTC — trigger nightly reconciliation batch job
resource "aws_cloudwatch_event_rule" "batch_trigger" {
  name                = "contoso-batch-trigger-${var.environment}"
  description         = "Trigger nightly reconciliation batch job"
  schedule_expression = "cron(0 2 * * ? *)"
}

resource "aws_cloudwatch_event_target" "batch" {
  rule      = aws_cloudwatch_event_rule.batch_trigger.name
  target_id = "ReconciliationBatchJob"
  arn       = aws_batch_job_queue.main.arn
  role_arn  = aws_iam_role.eventbridge.arn

  batch_target {
    job_definition = aws_batch_job_definition.reconciliation.arn
    job_name       = "contoso-reconciliation-nightly"
    job_attempts   = 2
  }
}
