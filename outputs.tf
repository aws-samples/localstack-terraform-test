# Output the S3 bucket name
output "s3_bucket_name" {
  value = aws_s3_bucket.my_bucket.id
}

output "state_machine_arn" {
  value = aws_sfn_state_machine.dynamodb_updater_workflow.arn
}

output "lambda_arn" {
  value = aws_lambda_function.upload_trigger_lambda.arn
}

output "file_name_check" {
  value = jsondecode(data.aws_dynamodb_table_item.test.item)["FileName"]["S"]
}
