output "corpus_bucket_name" {
  description = "S3 bucket holding PDFs and embeddings"
  value       = aws_s3_bucket.corpus.id
}

output "pdf_handler_function_arn" {
  description = "Lambda triggered on PDF uploads to pdfs/"
  value       = module.pdf_handler.lambda_function_arn
}

output "opensearch_collection_endpoint" {
  description = "OpenSearch Serverless collection endpoint"
  value       = aws_opensearchserverless_collection.vectors.collection_endpoint
}

output "opensearch_index_name" {
  description = "OpenSearch index name for chunk vectors"
  value       = "${var.project}-chunks"
}

output "chunks_queue_url" {
  description = "SQS queue URL receiving chunk batches for embedding"
  value       = aws_sqs_queue.chunks.url
}

output "chunks_dlq_url" {
  description = "SQS dead-letter queue URL for failed embedding batches"
  value       = aws_sqs_queue.chunks_dlq.url
}
