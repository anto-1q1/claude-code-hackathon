output "proxy_endpoint"        { value = aws_db_proxy.main.endpoint }
output "read_replica_endpoint" { value = aws_db_instance.read_replica.address }
output "primary_endpoint"      { value = aws_db_instance.primary.address }
