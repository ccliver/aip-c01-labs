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

variable "approved_model_ids" {
  description = "Bedrock model IDs permitted by the governance policy"
  type        = list(string)
  default = [
    "amazon.titan-embed-text-v2:0",
    "anthropic.claude-3-haiku-20240307-v1:0",
    "anthropic.claude-3-sonnet-20240229-v1:0",
  ]
}
