variable "environment"          { type = string }
variable "vpc_id"               { type = string }
variable "public_subnet_ids"    { type = list(string) }
variable "private_subnet_ids"   { type = list(string) }
variable "sg_alb_id"            { type = string }
variable "sg_webapp_id"         { type = string }
variable "db_proxy_endpoint"    { type = string }
variable "db_secret_arn"        { type = string }
variable "redis_endpoint"       { type = string }
variable "reports_bucket_name"  { type = string }
variable "reports_bucket_arn"   { type = string }
variable "acm_certificate_arn"  { type = string  default = "" }
