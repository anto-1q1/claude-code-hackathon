output "alb_dns_name"      { value = aws_lb.webapp.dns_name }
output "cloudfront_domain" { value = aws_cloudfront_distribution.webapp.domain_name }
output "cluster_arn"       { value = aws_ecs_cluster.main.arn }
output "warmup_task_arn"   { value = aws_ecs_task_definition.warmup.arn }
output "ecr_repo_url"      { value = aws_ecr_repository.webapp.repository_url }
