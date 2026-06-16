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

variable "embedding_model_id" {
  description = "Bedrock model ID for embeddings"
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}
