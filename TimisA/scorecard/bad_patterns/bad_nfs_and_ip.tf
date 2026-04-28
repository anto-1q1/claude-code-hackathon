# BAD PATTERN: Hardcoded on-prem IP addresses and NFS mount paths.
# B13: IPs should be DNS names (ADR-0001)
# B14: /mnt/reports and /tmp/flask_sessions must be replaced with S3 (ADR-0002, ADR-0004)

locals {
  # BAD: hardcoded on-prem DB host IP (ADR-0001 finding W1-1)
  db_host = "10.0.1.82"

  # BAD: hardcoded web app IP for warmup cron (ADR-0005 finding B1)
  webapp_warmup_url = "http://10.0.1.45/api/warmup"

  # BAD: NFS path hardcoded (ADR-0002 finding W1-2, B2)
  reports_path = "/mnt/reports"

  # BAD: local disk session path (ADR-0004 finding W1-3)
  session_dir = "/tmp/flask_sessions"
}

resource "aws_ecs_task_definition" "bad_nfs_mount" {
  family = "bad-nfs-task"

  container_definitions = jsonencode([{
    name  = "app"
    image = "contoso/webapp:latest"
    environment = [
      { name = "REPORT_PATH", value = "/mnt/reports" },
      { name = "SESSION_DIR", value = "/tmp/flask_sessions" },
      { name = "DB_HOST",     value = "10.0.1.82" },
    ]
  }])
}
