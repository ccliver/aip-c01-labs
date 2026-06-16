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

variable "models_to_evaluate" {
  description = "List of Bedrock model IDs to compare in the evaluation job"
  type        = list(string)
  default = [
    "anthropic.claude-3-haiku-20240307-v1:0",
    "amazon.nova-lite-v1:0",
  ]
}

variable "evaluation_task_type" {
  description = "Task type: Summarization | Classification | QuestionAndAnswer | Generation"
  type        = string
  default     = "QuestionAndAnswer"
}
