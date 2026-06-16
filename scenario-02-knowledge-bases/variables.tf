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

variable "embedding_model_arn" {
  description = "ARN of the Bedrock embedding model used by the knowledge base"
  type        = string
  default     = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
}

variable "chunking_strategy" {
  description = "Chunking strategy: FIXED_SIZE | HIERARCHICAL | SEMANTIC | NONE"
  type        = string
  default     = "FIXED_SIZE"
}
