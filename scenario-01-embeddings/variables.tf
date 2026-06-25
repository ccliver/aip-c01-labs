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

variable "chunk_size" {
  description = "RecursiveCharacterTextSplitter chunk size (characters)"
  type        = number
  default     = 1024
}

variable "chunk_overlap" {
  description = "RecursiveCharacterTextSplitter chunk overlap (characters)"
  type        = number
  default     = 100
}

variable "embedding_model_id" {
  description = "Bedrock model ID for embeddings"
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}
