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

variable "github_repo" {
  description = "GitHub repository in owner/name format for the pipeline source"
  type        = string
  default     = ""
}

variable "pipeline_branch" {
  description = "Branch that triggers the CI/CD pipeline"
  type        = string
  default     = "main"
}

variable "build_compute_type" {
  description = "CodeBuild compute type for Terraform and evaluation steps"
  type        = string
  default     = "BUILD_GENERAL1_SMALL"
}
