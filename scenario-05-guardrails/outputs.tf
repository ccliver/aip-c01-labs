output "guardrail_id" {
  description = "ID of the Bedrock Guardrail"
  value       = aws_bedrock_guardrail.this.guardrail_id
}

output "guardrail_arn" {
  description = "ARN of the Bedrock Guardrail"
  value       = aws_bedrock_guardrail.this.guardrail_arn
}

output "guardrail_version" {
  description = "Pinned guardrail version number"
  value       = aws_bedrock_guardrail_version.this.version
}

output "guardrail_id_ssm_parameter" {
  description = "SSM parameter name storing the guardrail ID"
  value       = aws_ssm_parameter.guardrail_id.name
}

output "guardrail_version_ssm_parameter" {
  description = "SSM parameter name storing the guardrail version"
  value       = aws_ssm_parameter.guardrail_version.name
}
