output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "webapp_alb_dns" {
  description = "ALB DNS name for the web application"
  value       = module.webapp.alb_dns_name
}

output "cloudfront_domain" {
  description = "CloudFront distribution domain"
  value       = module.webapp.cloudfront_domain
}

output "rds_proxy_endpoint" {
  description = "RDS Proxy endpoint for application connections"
  value       = module.database.proxy_endpoint
  sensitive   = true
}

output "rds_read_replica_endpoint" {
  description = "RDS read replica endpoint for analytical queries (5 internal teams)"
  value       = module.database.read_replica_endpoint
  sensitive   = true
}

output "redis_endpoint" {
  description = "ElastiCache Redis endpoint for session storage"
  value       = module.cache.redis_endpoint
  sensitive   = true
}

output "webapp_bucket_name" {
  description = "S3 bucket for web app PDF reports"
  value       = module.storage.webapp_bucket_name
}

output "batch_bucket_name" {
  description = "S3 bucket for batch reconciliation output"
  value       = module.storage.batch_bucket_name
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret containing DB credentials"
  value       = module.secrets.db_secret_arn
  sensitive   = true
}
