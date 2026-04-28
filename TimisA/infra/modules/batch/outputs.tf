output "job_queue_arn"      { value = aws_batch_job_queue.main.arn }
output "job_definition_arn" { value = aws_batch_job_definition.reconciliation.arn }
output "sns_topic_arn"      { value = aws_sns_topic.batch_notifications.arn }
output "ecr_repo_url"       { value = aws_ecr_repository.batch.repository_url }
