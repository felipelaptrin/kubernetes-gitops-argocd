provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project = "Kubernetes GitOps ArgoCD"
    }
  }
}
