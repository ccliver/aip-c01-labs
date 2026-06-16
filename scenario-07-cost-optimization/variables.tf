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

variable "monthly_budget_usd" {
  description = "Monthly spend cap for Bedrock in USD"
  type        = number
  default     = 50
}

variable "alert_email" {
  description = "Email address for budget and alarm notifications"
  type        = string
  default     = ""
}
