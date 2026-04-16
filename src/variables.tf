variable "environment" {
  description = "Environment name used to prefix resources"
  type        = string
  validation {
    condition     = contains(["dev"], var.environment)
    error_message = "Valid values for var: environment are (dev)."
  }
}

##############################
##### AWS RELATED
##############################
variable "aws_region" {
  description = "Region to deploy the resources"
  type        = string
}

##############################
##### NETWORKING
##############################
variable "vpc_azs_number" {
  description = "Number of AZs to use when deploying the VPC"
  type        = number
  default     = 2
}

variable "vpc_cidr" {
  description = "CIDR of the VPC"
  type        = string
}

##############################
##### KUBERNETES RELATED
##############################
variable "k8s_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.35"
}

variable "k8s_admin_role" {
  description = "IAM Principal ARN of the role that will be used by all the Kubernetes administrators"
  type        = string
}

variable "k8s_addons_versions" {
  description = "EKS addons versions. Check the available versions on https://docs.aws.amazon.com/eks/latest/userguide/updating-an-add-on.html"
  type = object({
    eks-pod-identity-agent = string
    aws-ebs-csi-driver     = string
  })
  default = {
    eks-pod-identity-agent = "v1.3.10-eksbuild.3"
    aws-ebs-csi-driver     = "v1.58.0-eksbuild.1"
  }
}
