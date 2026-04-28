# GOLDEN: IAM roles and policies with least-privilege.
# Good: scoped actions, specific resources, no wildcards on sensitive APIs.

data "aws_iam_policy_document" "ecs_task_s3" {
  statement {
    sid    = "ReadReportsBucket"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      "${var.reports_bucket_arn}/*",
    ]
  }

  statement {
    sid    = "ListReportsBucket"
    effect = "Allow"
    actions = ["s3:ListBucket"]
    resources = [var.reports_bucket_arn]
  }
}

data "aws_iam_policy_document" "ecs_task_secrets" {
  statement {
    sid    = "ReadAppSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = [var.db_secret_arn]
  }
}

resource "aws_iam_role" "ecs_task" {
  name = "contoso-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
