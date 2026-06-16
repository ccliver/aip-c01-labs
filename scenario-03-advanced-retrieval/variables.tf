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

variable "knowledge_base_id" {
  description = "ID of the Bedrock Knowledge Base from scenario-02 (set via tfvars)"
  type        = string
  default     = ""
}

variable "number_of_results" {
  description = "Default number of chunks to retrieve"
  type        = number
  default     = 5
}
