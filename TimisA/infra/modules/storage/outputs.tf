output "webapp_bucket_name" { value = aws_s3_bucket.webapp_reports.bucket }
output "webapp_bucket_arn"  { value = aws_s3_bucket.webapp_reports.arn }
output "batch_bucket_name"  { value = aws_s3_bucket.batch_output.bucket }
output "batch_bucket_arn"   { value = aws_s3_bucket.batch_output.arn }
output "reports_readonly_policy_arn" { value = aws_iam_policy.reports_readonly.arn }
