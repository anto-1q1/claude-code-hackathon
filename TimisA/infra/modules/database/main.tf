# RDS PostgreSQL Multi-AZ + Read Replica + RDS Proxy (ADR-0007)

resource "aws_db_subnet_group" "main" {
  name       = "contoso-db-${var.environment}"
  subnet_ids = var.subnet_ids
  tags       = { Name = "contoso-db-${var.environment}" }
}

# ── Primary RDS — Multi-AZ (ADR-0007 Layer 1) ─────────────────────────────────

resource "aws_db_instance" "primary" {
  identifier        = "contoso-reporting-db-${var.environment}"
  engine            = "postgres"
  engine_version    = "15.4"
  instance_class    = "db.m5.large"
  allocated_storage = 100
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "contoso"
  username = var.db_username
  # Password managed by Secrets Manager rotation — initial value from secret
  manage_master_user_password = false
  password                    = jsondecode(data.aws_secretsmanager_secret_version.db.secret_string)["password"]

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = var.security_group_ids

  # Multi-AZ for automatic failover (ADR-0007 Layer 1)
  multi_az = true

  # Never expose RDS on the public internet (CLAUDE.md reporting-db rule)
  publicly_accessible = false

  # Automated backups — 7-day retention (ADR-0007)
  backup_retention_period   = 7
  backup_window             = "02:30-03:00"  # after batch job window (02:00–04:00)
  maintenance_window        = "sun:04:00-sun:05:00"
  delete_automated_backups  = false

  # Point-in-time recovery enabled by default with backup_retention_period > 0

  # Prevent accidental deletion
  deletion_protection = var.environment == "prod" ? true : false
  skip_final_snapshot = var.environment == "prod" ? false : true
  final_snapshot_identifier = var.environment == "prod" ? "contoso-db-final-${var.environment}" : null

  tags = { Name = "contoso-reporting-db-${var.environment}", Role = "primary" }
}

data "aws_secretsmanager_secret_version" "db" {
  secret_id = var.db_secret_arn
}

# ── Read Replica — db.m5.xlarge (ADR-0007 Layer 2) ───────────────────────────

resource "aws_db_instance" "read_replica" {
  identifier          = "contoso-reporting-db-replica-${var.environment}"
  instance_class      = "db.m5.xlarge"  # larger: handles 5 teams' analytical queries
  replicate_source_db = aws_db_instance.primary.identifier

  # Replica inherits storage, engine, subnet group from primary
  vpc_security_group_ids = var.security_group_ids
  publicly_accessible    = false
  storage_encrypted      = true

  # Read replica in eu-west-1c (different AZ from primary eu-west-1a)
  availability_zone = "eu-west-1c"

  tags = { Name = "contoso-reporting-db-replica-${var.environment}", Role = "read-replica" }
}

# ── RDS Proxy — connection pooling (ADR-0007 Layer 3) ────────────────────────

data "aws_iam_policy_document" "rds_proxy_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds_proxy" {
  name               = "contoso-rds-proxy-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.rds_proxy_assume.json
}

resource "aws_iam_role_policy" "rds_proxy_secrets" {
  name = "rds-proxy-secrets-access"
  role = aws_iam_role.rds_proxy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = var.db_secret_arn
    }]
  })
}

resource "aws_db_proxy" "main" {
  name                   = "contoso-db-proxy-${var.environment}"
  debug_logging          = false
  engine_family          = "POSTGRESQL"
  idle_client_timeout    = 1800
  require_tls            = true
  role_arn               = aws_iam_role.rds_proxy.arn
  vpc_security_group_ids = var.security_group_ids
  vpc_subnet_ids         = var.subnet_ids

  auth {
    auth_scheme = "SECRETS"
    secret_arn  = var.db_secret_arn
    iam_auth    = "DISABLED"
  }

  tags = { Name = "contoso-db-proxy-${var.environment}" }
}

resource "aws_db_proxy_default_target_group" "main" {
  db_proxy_name = aws_db_proxy.main.name

  connection_pool_config {
    max_connections_percent      = 90
    max_idle_connections_percent = 50
    connection_borrow_timeout    = 120
  }
}

resource "aws_db_proxy_target" "main" {
  db_instance_identifier = aws_db_instance.primary.identifier
  db_proxy_name          = aws_db_proxy.main.name
  target_group_name      = aws_db_proxy_default_target_group.main.name
}
