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
