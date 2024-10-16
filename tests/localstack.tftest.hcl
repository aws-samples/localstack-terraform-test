provider "aws" {
  access_key = "test"
  secret_key = "test"
  region     = "eu-central-1"

  s3_use_path_style           = true
  skip_requesting_account_id  = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true

  endpoints {
    apigateway     = "http://localhost:4566"
    apigatewayv2   = "http://localhost:4566"
    cloudformation = "http://localhost:4566"
    cloudwatch     = "http://localhost:4566"
    cloudwatchlogs = "http://localhost:4566"
    dynamodb       = "http://localhost:4566"
    ec2            = "http://localhost:4566"
    es             = "http://localhost:4566"
    elasticache    = "http://localhost:4566"
    firehose       = "http://localhost:4566"
    iam            = "http://localhost:4566"
    kinesis        = "http://localhost:4566"
    lambda         = "http://localhost:4566"
    rds            = "http://localhost:4566"
    redshift       = "http://localhost:4566"
    route53        = "http://localhost:4566"
    s3             = "http://localhost:4566"
    secretsmanager = "http://localhost:4566"
    ses            = "http://localhost:4566"
    sns            = "http://localhost:4566"
    sqs            = "http://localhost:4566"
    ssm            = "http://localhost:4566"
    stepfunctions  = "http://localhost:4566"
    sts            = "http://localhost:4566"
  }
}

run "check_s3_bucket_name" {

  command = apply

  assert {
    condition     = output.s3_bucket_name == var.s3_bucket_name
    error_message = "S3 bucket name does not match"
  }

}

run "check_lambda_function" {

  command = apply

  assert {
    condition     = output.lambda_arn != null
    error_message = "Lambda function not created"
  }

}

run "check_name_of_filename_written_to_dynamodb" {

  command = apply

  assert {
    condition     = output.file_name_check == var.s3_object_key
    error_message = "Write to DynamoDB failed"
  }

}
