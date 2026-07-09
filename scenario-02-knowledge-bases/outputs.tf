output "knowledge_base_id" {
  description = "ID of the Bedrock Knowledge Base"
  value       = aws_bedrockagent_knowledge_base.this.id
}

output "knowledge_base_arn" {
  description = "ARN of the Bedrock Knowledge Base"
  value       = aws_bedrockagent_knowledge_base.this.arn
}

output "data_source_id" {
  description = "ID of the S3 data source"
  value       = aws_bedrockagent_data_source.pdfs.data_source_id
}

output "opensearch_index_name" {
  description = "AOSS index name used by the knowledge base"
  value       = local.kb_index_name
}
