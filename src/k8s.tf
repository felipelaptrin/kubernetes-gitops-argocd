##############################
##### ARGOCD
##############################
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = "argocd"

  create_namespace = true

  values = [file("${path.module}/../k8s/${var.environment}/bootstrap/argocd-values.yaml")]

  wait = true

  depends_on = [module.eks]

  lifecycle {
    ignore_changes = all
  }
}

##############################
##### GITOPS BRIDGE - CLUSTER SECRET
##############################
resource "kubernetes_secret" "argocd_cluster" {
  metadata {
    name      = "in-cluster"
    namespace = helm_release.argocd.namespace
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
      "environment"                    = var.environment
    }
    annotations = {
      "infra/vpc-id"         = module.vpc.vpc_id
      "infra/aws-region"     = var.aws_region
      "infra/aws-account-id" = local.account_id
      "infra/cluster-name"   = module.eks.cluster_name
    }
  }

  data = {
    server = "https://kubernetes.default.svc"
    config = jsonencode({ tlsClientConfig = { insecure = false } })
  }
}

##############################
##### ROOT APPLICATION
##############################
resource "kubernetes_manifest" "root_app" {
  manifest = yamldecode(templatefile("${path.module}/bootstrap/root-app.yaml", {
    gitops_repo_url      = var.gitops_repo_url
    gitops_repo_revision = var.gitops_repo_revision
    environment          = var.environment
  }))

  depends_on = [helm_release.argocd, kubernetes_secret.argocd_cluster]
}
