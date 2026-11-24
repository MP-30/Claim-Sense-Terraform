resource "aws_db_subnet_group" "app" {
  count      = local.app_enabled ? 1 : 0
  name       = "claimsense-local"
  subnet_ids = data.aws_subnets.default[0].ids
}

resource "aws_db_instance" "app" {
  count                       = local.app_enabled ? 1 : 0
  identifier                  = "claimsense-local"
  engine                      = "postgres"
  engine_version              = "18"
  instance_class              = "db.t3.micro"
  allocated_storage           = 20
  db_name                     = "claimsense"
  username                    = "claimsense"
  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.app[0].name
  publicly_accessible         = false
  skip_final_snapshot         = true
}

output "database_identifier" {
  value = local.app_enabled ? aws_db_instance.app[0].identifier : null
}

output "database_endpoint" {
  value = local.app_enabled ? aws_db_instance.app[0].endpoint : null
}
