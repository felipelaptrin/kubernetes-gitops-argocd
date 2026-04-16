resource "aws_sqs_queue" "terraform_queue" {
  name                    = "${var.environment}-terraform-cicd"
  sqs_managed_sse_enabled = true
}

module "bucket" {
  source      = "../modules/bucket"
  bucket_name = "${var.environment}-terraform-cd-ci-demo-${local.account_id}"
}
