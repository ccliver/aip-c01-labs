# TODO: output "trail_arn" — ARN of the CloudTrail trail
# TODO: output "invocation_log_bucket" — S3 bucket receiving Bedrock invocation logs

output "glue_database_name" {
  description = "Glue Data Catalog database containing the invocation_logs table"
  value       = aws_glue_catalog_database.bedrock_logs.name
}

output "glue_table_name" {
  description = "Glue table mapped over Bedrock model invocation logs in S3"
  value       = aws_glue_catalog_table.invocation_logs.name
}

output "athena_workgroup_name" {
  description = "Athena workgroup used to query the invocation_logs table"
  value       = aws_athena_workgroup.bedrock_logs.name
}

output "kb_corpus_glue_database_name" {
  description = "Glue Data Catalog database containing the kb_corpus_chunks table"
  value       = aws_glue_catalog_database.kb_corpus.name
}

output "kb_corpus_glue_table_name" {
  description = "Glue table mapped over scenario-01's KB corpus chunk metadata in S3"
  value       = aws_glue_catalog_table.kb_corpus_chunks.name
}
