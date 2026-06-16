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

variable "foundation_model_id" {
  description = "Bedrock model ID to associate with the prompt"
  type        = string
  default     = "anthropic.claude-3-haiku-20240307-v1:0"
}
