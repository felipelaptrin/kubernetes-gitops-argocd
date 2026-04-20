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

  values = [
    yamlencode({
      global = {
        tolerations = [{
          key      = "CriticalAddonsOnly"
          operator = "Equal"
          value    = "true"
          effect   = "NoSchedule"
        }]
      }
      extraObjects = [{
        apiVersion = "argoproj.io/v1alpha1"
        kind       = "Application"
        metadata = {
          name      = "bootstrap"
          namespace = "argocd"
        }
        spec = {
          project = "default"
          source = {
            repoURL        = var.gitops_repo_url
            targetRevision = var.gitops_repo_revision
            path           = "k8s/bootstrap"
          }
          destination = {
            server    = "https://kubernetes.default.svc"
            namespace = "argocd"
          }
          syncPolicy = {
            automated   = { prune = true, selfHeal = true }
            syncOptions = ["CreateNamespace=true"]
          }
        }
      }]
    })
  ]

  lifecycle {
    ignore_changes = all
  }
}

resource "tls_private_key" "argocd_repo" {
  algorithm = "ED25519"
}

resource "kubernetes_secret_v1" "argocd_repo" {
  depends_on = [helm_release.argocd]

  metadata {
    name      = "gitops-repo-ssh-key"
    namespace = helm_release.argocd.namespace
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type          = "git"
    url           = var.gitops_repo_url
    sshPrivateKey = tls_private_key.argocd_repo.private_key_openssh
  }
}

##############################
##### GITOPS BRIDGE - CLUSTER SECRET
##############################
resource "kubernetes_secret_v1" "argocd_cluster" {
  depends_on = [helm_release.argocd]

  metadata {
    name      = local.k8s_cluster_name
    namespace = helm_release.argocd.namespace
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
      "environment"                    = var.environment
    }
    annotations = {
      "environment"              = var.environment
      "vpc_id"                   = module.vpc.vpc_id
      "aws_region"               = var.aws_region
      "cluster_name"             = module.eks.cluster_name
      "gitops_repo_url"          = var.gitops_repo_url
      "gitops_repo_revision"     = var.gitops_repo_revision
      "gitops_addons_repo_path"  = var.gitops_addons_repo_path
      "gitops_apps_repo_path"    = var.gitops_apps_repo_path
      "acm_certificate_arn"      = module.acm.acm_certificate_arn
      "domain"                   = var.domain
      "karpenter_queue_name"     = module.karpenter.queue_name
      "karpenter_node_role_name" = local.karpenter_node_role_name
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

  name                            = substr("${local.prefix}-alb-controller", 0, 37)
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
##### EXTERNAL SECRETS IAM
##############################
module "external_secrets_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.7.0"

  name                                  = substr("${local.prefix}-external-secrets", 0, 37)
  attach_external_secrets_policy        = true
  external_secrets_secrets_manager_arns = ["arn:aws:secretsmanager:${var.aws_region}:*:*:*"]
  associations = {
    external_secrets = {
      cluster_name    = module.eks.cluster_name
      namespace       = "external-secrets"
      service_account = "external-secrets"
    }
  }
}

##############################
##### EXTERNAL DNS IAM
##############################
module "external_dns_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.7.0"

  name                          = substr("${local.prefix}-external-dns", 0, 37)
  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = [data.aws_route53_zone.this.arn]
  associations = {
    external_dns = {
      cluster_name    = module.eks.cluster_name
      namespace       = "external-dns"
      service_account = "external-dns"
    }
  }
}

##############################
##### AWS EBS CSI DRIVER IAM
##############################
module "ebs_csi_driver_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.7.0"

  name                      = substr("${local.prefix}-ebs-csi-driver", 0, 37)
  attach_aws_ebs_csi_policy = true
  associations = {
    ebs_csi_driver = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
    }
  }
}

##############################
##### KARPENTER
##############################
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.18.0"

  cluster_name         = module.eks.cluster_name
  node_iam_role_arn    = module.eks.eks_managed_node_groups["critical-addons"].iam_role_arn
  namespace            = "karpenter"
  create_access_entry  = false
  create_node_iam_role = false
  node_iam_role_additional_policies = {
    ssm = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}
