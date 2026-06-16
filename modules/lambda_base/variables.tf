variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "handler" {
  description = "Lambda handler in file.function form"
  type        = string
  default     = "handler.lambda_handler"
}

variable "runtime" {
  description = "Lambda runtime identifier"
  type        = string
  default     = "python3.12"
}

variable "source_dir" {
  description = "Path to the Lambda source directory (relative to the scenario root)"
  type        = string
}

variable "execution_role_arn" {
  description = "IAM role ARN for the Lambda function"
  type        = string
}

variable "environment_variables" {
  description = "Environment variables to inject into the function"
  type        = map(string)
  default     = {}
}

variable "timeout" {
  description = "Function timeout in seconds"
  type        = number
  default     = 30
}

variable "memory_size" {
  description = "Function memory allocation in MB"
  type        = number
  default     = 256
}
