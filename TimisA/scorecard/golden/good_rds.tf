# GOLDEN: RDS with encryption, Multi-AZ, automated backups, no public access.
# Good: deletion_protection, skip_final_snapshot=false, storage_encrypted, Multi-AZ.

resource "aws_db_instance" "main" {
  identifier        = "contoso-db-${var.environment}"
  engine            = "postgres"
  engine_version    = "15.4"
  instance_class    = "db.m5.large"
  allocated_storage = 100

  db_name  = var.db_name
  username = var.db_username
  password = data.aws_secretsmanager_secret_version.db.secret_string

  multi_az               = true
  publicly_accessible    = false
  storage_encrypted      = true
  deletion_protection    = true
  skip_final_snapshot    = false
  final_snapshot_identifier = "contoso-db-final-${var.environment}"

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  vpc_security_group_ids = [var.db_sg_id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  tags = {
    Name        = "contoso-db-${var.environment}"
    Environment = var.environment
    ManagedBy   = "terraform"
    DataClass   = "confidential"
  }
}
