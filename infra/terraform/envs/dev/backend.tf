terraform {
  backend "s3" {
    bucket         = "listmonk2-dev-tfstate-c41f40ec"
    key            = "envs/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "listmonk2-dev-tflock"
    encrypt        = true
  }
}
