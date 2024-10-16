# Define variables
variable "s3_bucket_name" {
  description = "The name of the S3 bucket"
  type        = string
  default     = "my-test-bucket"
}

variable "dynamodb_table_name" {
  description = "The name of the DynamoDB table"
  type        = string
  default     = "Files"
}

variable "dynamodb_hash_key" {
  description = "The hash key of the DynamoDB table"
  type        = string
  default     = "FileName"
}

variable "lambda_name" {
  description = "The name of the Lambda function"
  type        = string
  default     = "upload_trigger_lambda"
}


variable "s3_object_key" {
  description = "The key of the S3 object"
  type        = string
  default     = "README.md"
}

variable "sfn_name" {
  description = "The name of the Step Functions state machine"
  type        = string
  default     = "UploadStateMachine"
}
