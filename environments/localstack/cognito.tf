resource "aws_cognito_user_pool" "portal" {
  count = local.app_enabled ? 1 : 0
  name  = "claimsense-local"

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  password_policy {
    minimum_length    = 12
    require_uppercase = true
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
  }
}

resource "aws_cognito_user_pool_client" "portal" {
  count                         = local.app_enabled ? 1 : 0
  name                          = "claimsense-portal"
  user_pool_id                  = aws_cognito_user_pool.portal[0].id
  generate_secret               = false
  explicit_auth_flows           = ["ALLOW_USER_PASSWORD_AUTH"]
  prevent_user_existence_errors = "ENABLED"
  access_token_validity         = 30

  token_validity_units {
    access_token = "minutes"
  }
}

output "cognito_user_pool_id" {
  value = local.app_enabled ? aws_cognito_user_pool.portal[0].id : null
}

output "cognito_client_id" {
  value = local.app_enabled ? aws_cognito_user_pool_client.portal[0].id : null
}
