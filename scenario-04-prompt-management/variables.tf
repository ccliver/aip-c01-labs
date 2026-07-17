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
  description = "Bedrock inference profile ID to associate with the prompt"
  type        = string
  default     = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
}
