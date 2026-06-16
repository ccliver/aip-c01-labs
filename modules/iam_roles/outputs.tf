output "lambda_bedrock_exec_role_arn" {
  description = "ARN of the Lambda execution role with Bedrock access"
  value       = null # TODO: replace with aws_iam_role.lambda_bedrock_exec.arn
}
