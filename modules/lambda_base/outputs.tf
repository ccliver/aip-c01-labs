output "function_arn" {
  description = "ARN of the deployed Lambda function"
  value       = null # TODO: replace with aws_lambda_function.this.arn
}

output "function_name" {
  description = "Name of the deployed Lambda function"
  value       = null # TODO: replace with aws_lambda_function.this.function_name
}

output "log_group_name" {
  description = "CloudWatch log group name for this function"
  value       = null # TODO: replace with aws_cloudwatch_log_group.this.name
}
