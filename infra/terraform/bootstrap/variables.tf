variable "aws_region" {
  type = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "listmonk2"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "owner" {
  type    = string
  default = "devops-team"
}