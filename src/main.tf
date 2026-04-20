##############################
##### NETWORKING
##############################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "v6.6.1"

  name = local.prefix
  cidr = var.vpc_cidr

  azs              = local.azs
  private_subnets  = local.private_subnets
  public_subnets   = local.public_subnets
  database_subnets = local.database_subnets

  enable_nat_gateway = true
  single_nat_gateway = true

  # VPC Requirements: https://docs.aws.amazon.com/eks/latest/userguide/network-reqs.html
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"                 = 1
    "kubernetes.io/cluster/${local.k8s_cluster_name}" = "owned"
    "karpenter.sh/discovery"                          = local.k8s_cluster_name
  }
  public_subnet_tags = {
    "kubernetes.io/role/elb"                          = 1
    "kubernetes.io/cluster/${local.k8s_cluster_name}" = "owned"
  }
}


##############################
##### KUBERNETES
##############################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "v21.18.0"

  name               = local.k8s_cluster_name
  kubernetes_version = var.k8s_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  node_security_group_tags = {
    "karpenter.sh/discovery" = local.k8s_cluster_name
  }

  endpoint_public_access                   = true
  enable_cluster_creator_admin_permissions = false

  addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
    }
    eks-pod-identity-agent = {
      addon_version = var.k8s_addons_versions.eks-pod-identity-agent
    }
    aws-ebs-csi-driver = {
      addon_version = var.k8s_addons_versions.aws-ebs-csi-driver
    }
  }

  # Best way to grant users access to Kubernetes API: https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html
  access_entries = {
    sso_admins = {
      principal_arn = var.k8s_admin_role
      policy_associations = {
        sso_admins = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  # Using EKS-Optimized Images: https://aws.amazon.com/blogs/containers/amazon-eks-optimized-amazon-linux-2023-amis-now-available/
  eks_managed_node_groups = {
    critical-addons = {
      ami_type = "AL2023_ARM_64_STANDARD"
      instance_types = [
        "m6g.large"
      ]
      min_size     = 2
      max_size     = 3
      desired_size = 2
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
      }
      iam_role_additional_policies = {
        ssm = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }
      taints = {
        critical_addons_only = {
          key    = "CriticalAddonsOnly" # Reference: https://docs.aws.amazon.com/eks/latest/userguide/critical-workload.html
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  node_security_group_additional_rules = {
    ingress_cluster_istio_webhook = {
      source_cluster_security_group = true
      description                   = "Cluster control plane calls Istio webhook"
      from_port                     = 15017
      to_port                       = 15017
      protocol                      = "tcp"
      type                          = "ingress"
    }
  }
}

##############################
##### ACM
##############################
module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "6.3.0"

  domain_name         = "*.${var.domain}"
  zone_id             = data.aws_route53_zone.this.zone_id
  validation_method   = "DNS"
  wait_for_validation = true
}
