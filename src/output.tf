output "deployed_environment" {
  description = "Account ID and Environment Name deployed"
  value       = "Environment [${var.environment}] => Account ${local.account_id}"
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "k8s_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "argocd_deploy_public_key" {
  description = "SSH public key to add as a read-only deploy key in the GitHub repository"
  value       = tls_private_key.argocd_repo.public_key_openssh
}
