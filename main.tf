
# Create an S3 Bucket
resource "aws_s3_bucket" "my_bucket" {
  # checkov:skip=CKV2_AWS_62: "Ensure S3 buckets should have event notifications enabled"
  # checkov:skip=CKV_AWS_18: "Ensure the S3 bucket has access logging enabled"
  # checkov:skip=CKV_AWS_144: "Ensure that S3 bucket has cross-region replication enabled"
  # checkov:skip=CKV_AWS_145: "Ensure that S3 buckets are encrypted with KMS by default"
  bucket = var.s3_bucket_name
}

resource "aws_s3_bucket_versioning" "my_bucket_versioning" {
  bucket = aws_s3_bucket.my_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "my_bucket_policy" {
  bucket                  = aws_s3_bucket.my_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "my_bucket_encryption" {
  bucket = aws_s3_bucket.my_bucket.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.my_bucket.id

  rule {
    id = "retention-policy"

    expiration {
      days = 7
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    status = "Enabled"
  }
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Customer managed KMS key used to encrypt the DynamoDB table and the CloudWatch log groups
resource "aws_kms_key" "this" {
  description             = "CMK for the DynamoDB table and CloudWatch log groups"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  # In a key policy, Resource "*" refers to this key only.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAccountPermissions"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudWatchLogsUseOfTheKey"
        Effect    = "Allow"
        Principal = { Service = "logs.${data.aws_region.current.name}.amazonaws.com" }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*",
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:*"
          }
        }
      },
    ]
  })
}

resource "aws_kms_alias" "this" {
  name          = "alias/localstack-terraform-test"
  target_key_id = aws_kms_key.this.key_id
}

# Create a DynamoDB Table
resource "aws_dynamodb_table" "files" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = var.dynamodb_hash_key
  attribute {
    name = var.dynamodb_hash_key
    type = "S"
  }
  point_in_time_recovery {
    enabled = true
  }
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.this.arn
  }
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# Create an IAM Role for Lambda
resource "aws_iam_role" "lambda_execution_role" {
  name               = "lambda_execution_role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    effect = "Allow"

    actions = [
      "states:StartExecution",
    ]

    resources = [
      aws_sfn_state_machine.dynamodb_updater_workflow.arn,
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["${aws_cloudwatch_log_group.MyLambdaLogGroup.arn}:*"]
  }

  # Required for active X-Ray tracing. These X-Ray actions do not support
  # resource-level permissions, so the resource must be "*".
  # See https://docs.aws.amazon.com/lambda/latest/dg/services-xray.html
  statement {
    effect = "Allow"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "lambda_policy" {
  policy      = data.aws_iam_policy_document.lambda_policy.json
  name        = "lambda_dynamodb_policy"
  description = "Policy to allow Lambda to start a Step Function"
}

# Attach the Lambda policy to the Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
  policy_arn = aws_iam_policy.lambda_policy.arn
  role       = aws_iam_role.lambda_execution_role.name
}

# tflint-ignore: terraform_required_providers
data "archive_file" "python_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/"
  output_path = "${path.module}/lambda/lambda-trigger-sm.zip"
}

# Create a Lambda Function
resource "aws_lambda_function" "upload_trigger_lambda" {
  # checkov:skip=CKV_AWS_117: "Test Lambda function does not need to be inside a VPC"
  # checkov:skip=CKV_AWS_116: "Test Lambda function does not need a Dead Letter Queue(DLQ)"
  # checkov:skip=CKV_AWS_173: "Test Lambda function does not need encryption for environmental variables"
  # checkov:skip=CKV_AWS_272: "Test Lambda function does not need code-signing"
  # checkov:skip=CKV_AWS_115: "Test Lambda function does not need function-level concurrent execution limit"
  function_name = var.lambda_name
  handler       = "index.lambda_handler"
  runtime       = "python3.12"
  role          = aws_iam_role.lambda_execution_role.arn

  filename         = "${path.module}/lambda/lambda-trigger-sm.zip"
  source_code_hash = data.archive_file.python_zip.output_base64sha256
  timeout          = 120

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      SM_ARN = aws_sfn_state_machine.dynamodb_updater_workflow.arn
    }
  }
}

resource "aws_cloudwatch_log_group" "MyLambdaLogGroup" {
  name              = "/aws/lambda/${aws_lambda_function.upload_trigger_lambda.function_name}"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = aws_kms_key.this.arn
}

resource "aws_cloudwatch_log_group" "MySFNLogGroup" {
  name_prefix       = "/aws/vendedlogs/states/${var.sfn_name}-"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = aws_kms_key.this.arn
}

data "aws_iam_policy_document" "sf_policy" {
  statement {
    effect = "Allow"

    actions = [
      "dynamodb:PutItem",
    ]

    resources = [
      aws_dynamodb_table.files.arn,
    ]
  }

  # Required to write items to the DynamoDB table encrypted with the customer managed key.
  statement {
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]

    resources = [
      aws_kms_key.this.arn,
    ]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["dynamodb.${data.aws_region.current.name}.amazonaws.com"]
    }
  }

  # Required for Step Functions logging to CloudWatch Logs. The CloudWatch Logs
  # vended log delivery APIs do not support resource-level permissions, so the
  # resource must be "*".
  # See https://docs.aws.amazon.com/step-functions/latest/dg/cw-logs.html#cloudwatch-iam-policy
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups"
    ]
    resources = ["*"]
  }

  # Required for X-Ray tracing of the state machine. These X-Ray actions do not
  # support resource-level permissions, so the resource must be "*".
  # See https://docs.aws.amazon.com/step-functions/latest/dg/procedure-enable-xray-tracing.html
  statement {
    effect = "Allow"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
      "xray:GetSamplingRules",
      "xray:GetSamplingTargets",
    ]
    resources = ["*"]
  }
}

# Attach a policy to the IAM role that allows PutItem in DynamoDB and CloudWatch Logs
resource "aws_iam_policy" "state_machine_policy" {
  name        = "state_machine_policy"
  description = "Policy to allow PutItem in DynamoDB and permissions for CloudWatch Logs"
  policy      = data.aws_iam_policy_document.sf_policy.json

}

data "aws_iam_policy_document" "assume_role_sf" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# Create an IAM role for the Step Function
resource "aws_iam_role" "step_function_role" {
  name               = "step_function_role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_sf.json

}

resource "aws_iam_role_policy_attachment" "attach_state_machine_policy" {
  policy_arn = aws_iam_policy.state_machine_policy.arn
  role       = aws_iam_role.step_function_role.name
}

resource "aws_sfn_state_machine" "dynamodb_updater_workflow" {
  name = var.sfn_name
  tracing_configuration {
    enabled = true
  }
  definition = jsonencode({
    Comment = "A Step Function that writes to DynamoDB",
    StartAt = "Upload",
    States = {
      Upload = {
        Type     = "Task",
        Resource = "arn:aws:states:::dynamodb:putItem",
        Parameters = {
          "TableName" : aws_dynamodb_table.files.name,
          "Item" : {
            "FileName" : { "S.$" : "$.fileName" },
          }
        },
        End = true,
      }
    }
  })
  role_arn = aws_iam_role.step_function_role.arn
  logging_configuration {
    level                  = "ALL"
    include_execution_data = true
    log_destination        = "${aws_cloudwatch_log_group.MySFNLogGroup.arn}:*"
  }
  timeouts {
    create = "1m"
  }
}

resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.upload_trigger_lambda.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.my_bucket.arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.my_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.upload_trigger_lambda.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_bucket]
}

# tflint-ignore: terraform_required_providers
resource "time_sleep" "wait" {
  create_duration = "15s"
  triggers = {
    s3_object = local.key_json
  }

}

data "aws_dynamodb_table_item" "test" {

  table_name = var.dynamodb_table_name
  key        = time_sleep.wait.triggers.s3_object
}
locals {
  key_json = jsonencode({
    "FileName" = {
      "S" = aws_s3_object.object.key
    }
  })
  # tflint-ignore: terraform_unused_declarations
  first_decode = jsondecode(data.aws_dynamodb_table_item.test.item)
}

resource "aws_s3_object" "object" {
  bucket     = var.s3_bucket_name
  key        = var.s3_object_key
  source     = "${path.root}/${var.s3_object_key}"
  depends_on = [aws_s3_bucket.my_bucket, aws_s3_bucket_notification.bucket_notification]
}
