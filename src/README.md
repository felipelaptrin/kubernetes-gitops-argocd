# src

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.14.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.31 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.31 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_eks"></a> [eks](#module\_eks) | terraform-aws-modules/eks/aws | v21.18.0 |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | terraform-aws-modules/vpc/aws | v6.6.1 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | Region to deploy the resources | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name used to prefix resources | `string` | n/a | yes |
| <a name="input_k8s_addons_versions"></a> [k8s\_addons\_versions](#input\_k8s\_addons\_versions) | EKS addons versions. Check the available versions on https://docs.aws.amazon.com/eks/latest/userguide/updating-an-add-on.html | <pre>object({<br/>    eks-pod-identity-agent = string<br/>    aws-ebs-csi-driver     = string<br/>  })</pre> | <pre>{<br/>  "aws-ebs-csi-driver": "v1.58.0-eksbuild.1",<br/>  "eks-pod-identity-agent": "v1.3.10-eksbuild.3"<br/>}</pre> | no |
| <a name="input_k8s_admin_role"></a> [k8s\_admin\_role](#input\_k8s\_admin\_role) | IAM Principal ARN of the role that will be used by all the Kubernetes administrators | `string` | n/a | yes |
| <a name="input_k8s_version"></a> [k8s\_version](#input\_k8s\_version) | EKS Kubernetes version. | `string` | `"1.35"` | no |
| <a name="input_vpc_azs_number"></a> [vpc\_azs\_number](#input\_vpc\_azs\_number) | Number of AZs to use when deploying the VPC | `number` | `2` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | CIDR of the VPC | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_deployed_environment"></a> [deployed\_environment](#output\_deployed\_environment) | Account ID and Environment Name deployed |
| <a name="output_k8s_cluster_name"></a> [k8s\_cluster\_name](#output\_k8s\_cluster\_name) | EKS cluster name |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | VPC ID |
<!-- END_TF_DOCS -->
