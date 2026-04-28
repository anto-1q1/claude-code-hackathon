variable "environment"        { type = string }
variable "subnet_ids"         { type = list(string) }
variable "security_group_ids" { type = list(string) }
variable "db_username"        { type = string }
variable "db_secret_arn"      { type = string }
