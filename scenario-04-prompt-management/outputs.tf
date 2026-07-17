output "prompt_arn" {
  description = "ARN of the query-expansion prompt's working draft (pass as Converse modelId)"
  value       = aws_bedrockagent_prompt.query_expansion.arn
}

output "prompt_registry_table_name" {
  description = "DynamoDB table the hybrid search script reads to resolve the active prompt version"
  value       = aws_dynamodb_table.prompt_registry.name
}

output "bedrock_invocation_log_group_name" {
  description = "CloudWatch Log Group receiving Bedrock model invocation logs"
  value       = aws_cloudwatch_log_group.bedrock_invocation.name
}

output "bedrock_invocation_logs_bucket_name" {
  description = "S3 bucket receiving Bedrock model invocation logs"
  value       = aws_s3_bucket.bedrock_invocation_logs.id
}

# TODO: output "invoke_function_arn" — Lambda that invokes the versioned prompt
