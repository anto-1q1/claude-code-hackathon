# GOLDEN: Secrets Manager with rotation, random password, never a variable.
# Good: random_password resource, auto-rotation, no plaintext in .tf.

resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "contoso/${var.environment}/db-credentials"
  description             = "RDS credentials — managed by Terraform, rotated every 180 days"
  recovery_window_in_days = 7

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    host     = aws_db_proxy.main.endpoint
    port     = 5432
    dbname   = var.db_name
  })
}

resource "aws_secretsmanager_secret_rotation" "db_credentials" {
  secret_id           = aws_secretsmanager_secret.db_credentials.id
  rotation_lambda_arn = var.rotation_lambda_arn

  rotation_rules {
    automatically_after_days = 180
  }
}
