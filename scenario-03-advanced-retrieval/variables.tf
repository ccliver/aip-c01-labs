variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project tag applied to all resources"
  type        = string
  default     = "aip-c01-labs"
}

variable "claude_model_id" {
  description = "Bedrock inference profile ID for query expansion"
  type        = string
  default     = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
}

variable "embedding_model_id" {
  description = "Bedrock model ID for Titan text embeddings"
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}

variable "rerank_model_id" {
  description = "Bedrock model ID for reranking — must be available in var.aws_region (cohere.rerank-v3-5:0 for us-east-1, amazon.rerank-v1:0 for us-west-2)"
  type        = string
  default     = "cohere.rerank-v3-5:0"
}

variable "bm25_weight" {
  description = "Weight for BM25 keyword scores in hybrid search (must sum to 1.0 with knn_weight)"
  type        = number
  default     = 0.3
}

variable "knn_weight" {
  description = "Weight for kNN vector scores in hybrid search (must sum to 1.0 with bm25_weight)"
  type        = number
  default     = 0.7
}

variable "top_k" {
  description = "Number of results to retrieve and rerank"
  type        = number
  default     = 5
}
