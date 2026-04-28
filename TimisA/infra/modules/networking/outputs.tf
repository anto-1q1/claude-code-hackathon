output "vpc_id"              { value = aws_vpc.main.id }
output "public_subnet_ids"  { value = aws_subnet.public[*].id }
output "private_subnet_ids" { value = aws_subnet.private[*].id }
output "sg_alb_id"          { value = aws_security_group.alb.id }
output "sg_webapp_id"       { value = aws_security_group.webapp.id }
output "sg_batch_id"        { value = aws_security_group.batch.id }
output "sg_db_id"           { value = aws_security_group.db.id }
output "sg_cache_id"        { value = aws_security_group.cache.id }
