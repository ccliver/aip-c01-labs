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

variable "throttle_burst_limit" {
  description = "Invoke rate used to simulate ThrottlingException in probe tests"
  type        = number
  default     = 1
}
