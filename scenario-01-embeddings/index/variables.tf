variable "opensearch_endpoint" {
  description = "AOSS collection endpoint, including https:// scheme (from scenario-01-embeddings output opensearch_collection_endpoint)"
  type        = string
}

variable "opensearch_index_name" {
  description = "Index name to create (from scenario-01-embeddings output opensearch_index_name)"
  type        = string
}

variable "aws_region" {
  description = "AWS region for SigV4 signing of AOSS requests"
  type        = string
  default     = "us-east-1"
}

variable "embed_dimensions" {
  description = "Embedding vector dimension"
  type        = number
  default     = 1024
}
