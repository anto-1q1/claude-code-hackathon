# ElastiCache Redis for Flask session storage (ADR-0004)

resource "aws_elasticache_subnet_group" "main" {
  name       = "contoso-cache-${var.environment}"
  subnet_ids = var.subnet_ids
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "contoso-webapp-cache-${var.environment}"
  description          = "Redis for Flask session storage — contoso webapp"

  node_type            = "cache.t3.micro"
  port                 = 6379
  num_cache_clusters   = 2  # primary + replica for Multi-AZ failover (ADR-0004)

  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = var.security_group_ids

  # Encryption (ADR-0004)
  at_rest_encryption_enabled  = true
  transit_encryption_enabled  = true
  auth_token                  = null  # token auth disabled; use SG + TLS instead

  automatic_failover_enabled = true
  multi_az_enabled           = true

  # Session TTL aligned with app (8h — ADR-0004)
  parameter_group_name = aws_elasticache_parameter_group.redis.name

  tags = { Name = "contoso-webapp-cache-${var.environment}" }
}

resource "aws_elasticache_parameter_group" "redis" {
  name   = "contoso-redis7-${var.environment}"
  family = "redis7"

  parameter {
    name  = "maxmemory-policy"
    value = "volatile-ttl"  # evict keys with TTL set (sessions) when memory full
  }
}
