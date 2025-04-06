terraform {
  backend "s3" {
    bucket         = var.terraform_state_bucket_name
    key            = "terraform/state/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-locking"
    encrypt        = true
  }
}
