terraform {

  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"

      # LocalStack does not support validation AWS Step Functions definition introduced in v5.67.0
      # See https://github.com/localstack/localstack/issues/11553 and https://github.com/localstack/localstack/pull/11660
      version = "<= 5.66.0"
    }
  }
}