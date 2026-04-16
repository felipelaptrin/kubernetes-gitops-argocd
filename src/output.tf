output "deployed_environment" {
  description = "Account ID and Environment Name to be deployed"
  value       = "Environment [${var.environment}] => Account ${local.account_id}"
}
