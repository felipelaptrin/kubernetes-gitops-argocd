##############################
##### ARGOCD
##############################
resource "helm_release" "argocd" {
  depends_on = [module.eks]

  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = "argocd"
  create_namespace = true
  wait             = true

  lifecycle {
    ignore_changes = all
  }
}

##############################
##### GITOPS BRIDGE - CLUSTER SECRET
##############################
resource "kubernetes_secret" "argocd_cluster" {
  depends_on = [helm_release.argocd]

  metadata {
    name      = local.k8s_cluster_name
    namespace = helm_release.argocd.namespace
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
      "environment"                    = var.environment
    }
    annotations = {
      "environment"             = var.environment
      "vpc_id"                  = module.vpc.vpc_id
      "aws_region"              = var.aws_region
      "cluster_name"            = module.eks.cluster_name
      "gitops_repo_url"         = var.gitops_repo_url
      "gitops_repo_revision"    = var.gitops_repo_revision
      "gitops_addons_repo_path" = var.gitops_addons_repo_path
      "gitops_apps_repo_path"   = var.gitops_apps_repo_path
    }
  }

  data = {
    name   = var.environment
    server = "https://kubernetes.default.svc"
    config = jsonencode({ tlsClientConfig = { insecure = false } }) # Insecure because it's in-cluster
  }
}

##############################
##### AWS LOAD BALANCER CONTROLLER IAM
##############################
module "alb_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.7.0"

  name                            = "${local.prefix}-alb-controller"
  attach_aws_lb_controller_policy = true
  associations = {
    alb_controller = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }
}

##############################
##### ROOT APPLICATION
##############################
resource "kubernetes_manifest" "root_app" {
  depends_on = [helm_release.argocd, kubernetes_secret.argocd_cluster, module.alb_controller_pod_identity]

  manifest = yamldecode(templatefile("${path.module}/bootstrap/bootstrap.yaml", {
    gitops_repo_url      = var.gitops_repo_url
    gitops_repo_revision = var.gitops_repo_revision
    environment          = var.environment
  }))

}
