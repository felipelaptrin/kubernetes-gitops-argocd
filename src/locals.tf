locals {
  account_id = data.aws_caller_identity.current.account_id
  project    = "kubernetes-gitops-argocd"
  prefix     = "${var.environment}-${local.project}"

  # Networking
  azs              = slice(data.aws_availability_zones.available.names, 0, var.vpc_azs_number)
  private_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k)]
  public_subnets   = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 4)]
  database_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 8)]

  # Kubernetes
  k8s_cluster_name = local.prefix // This local var is created only to avoid cyclical dependency between vpc and eks modules

}
