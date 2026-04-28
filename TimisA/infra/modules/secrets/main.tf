# Password is generated here — never accepted as input variable (ADR-0003)
resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# ── DB Credentials Secret (ADR-0003) ─────────────────────────────────────────

resource "aws_secretsmanager_secret" "db" {
  name        = "contoso/${var.environment}/db-credentials"
  description = "RDS PostgreSQL master credentials for Contoso Financial"

  # Prevent accidental deletion of credentials in production
  recovery_window_in_days = var.environment == "prod" ? 7 : 0

  tags = { Name = "contoso-db-credentials-${var.environment}" }
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    engine   = "postgres"
    port     = 5432
  })

  lifecycle {
    # After initial creation, rotation manages subsequent versions
    ignore_changes = [secret_string]
  }
}

# Automatic rotation every 6 months (ADR-0003)
resource "aws_secretsmanager_secret_rotation" "db" {
  secret_id           = aws_secretsmanager_secret.db.id
  rotation_lambda_arn = aws_lambda_function.rotation.arn

  rotation_rules {
    automatically_after_days = 180
  }

  depends_on = [aws_lambda_permission.secrets_manager]
}

# ── Rotation Lambda ────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rotation_lambda" {
  name               = "contoso-secrets-rotation-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "rotation_lambda_basic" {
  role       = aws_iam_role.rotation_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "rotation_lambda_secrets" {
  name = "secrets-rotation-access"
  role = aws_iam_role.rotation_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:PutSecretValue",
                    "secretsmanager:DescribeSecret", "secretsmanager:UpdateSecretVersionStage"]
        Resource = aws_secretsmanager_secret.db.arn
      },
      {
        Effect   = "Allow"
        Action   = ["rds-db:connect"]
        Resource = "*"
      }
    ]
  })
}

# Rotation Lambda placeholder — in a real deployment, use the AWS-provided
# SecretsManager rotation function for RDS PostgreSQL from the Serverless
# Application Repository (arn:aws:serverlessrepo:us-east-1:297356227824:applications/SecretsManagerRDSPostgreSQLRotationSingleUser)
resource "aws_lambda_function" "rotation" {
  function_name = "contoso-db-rotation-${var.environment}"
  role          = aws_iam_role.rotation_lambda.arn
  runtime       = "python3.12"
  handler       = "lambda_function.lambda_handler"
  filename      = "${path.module}/rotation_placeholder.zip"
  description   = "RDS credential rotation — replace with SecretsManager SAR app in production"

  environment {
    variables = {
      SECRETS_MANAGER_ENDPOINT = "https://secretsmanager.eu-west-1.amazonaws.com"
    }
  }

  tags = { Name = "contoso-db-rotation-${var.environment}" }
}

resource "aws_lambda_permission" "secrets_manager" {
  statement_id  = "AllowSecretsManagerInvocation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rotation.function_name
  principal     = "secretsmanager.amazonaws.com"
  source_arn    = aws_secretsmanager_secret.db.arn
}
