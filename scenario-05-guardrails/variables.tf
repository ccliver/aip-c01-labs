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

variable "blocked_topics" {
  description = "List of topic names to deny in the guardrail"
  type        = list(string)
  default     = ["competitor-products", "investment-advice"]
}

variable "pii_action" {
  description = "Action for PII detection: BLOCK | ANONYMIZE"
  type        = string
  default     = "ANONYMIZE"
}
