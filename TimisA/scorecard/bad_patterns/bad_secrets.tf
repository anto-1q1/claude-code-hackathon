# BAD PATTERN: Hardcoded secrets in IaC — should be blocked by PreToolUse hook.
# The hook in TimisA/.claude/hooks/check-secrets.py must catch these.

resource "aws_db_instance" "bad_hardcoded_pw" {
  identifier = "contoso-db"
  engine     = "postgres"

  # BAD: hardcoded password — hook should block this write
  username = "admin"
  password = "C0nt0s0#2019"

  # BAD: no encryption
  storage_encrypted = false

  # BAD: publicly accessible
  publicly_accessible = true

  # BAD: no deletion protection
  deletion_protection = false

  # BAD: skip final snapshot
  skip_final_snapshot = true

  # BAD: no backups
  backup_retention_period = 0
}

variable "db_password" {
  # BAD: secret as plain variable — will appear in state and plan output
  default = "SuperSecret123!"
}

locals {
  # BAD: API key hardcoded in locals
  api_key = "AKIAIOSFODNN7EXAMPLE"
}
