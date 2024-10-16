terraform {

  required_version = "~> 1.9"

  required_providers {
    aws = {
      source = "hashicorp/aws"

      # LocalStack does not support validation AWS Step Functions definition introduced in v5.67.0
      version = "<= 5.66.0"
    }
  }
}