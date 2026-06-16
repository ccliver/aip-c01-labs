variable "project" {
  description = "Project prefix used in role names"
  type        = string
}

variable "allowed_bedrock_models" {
  description = "List of Bedrock model ARNs this role may invoke (use [\"*\"] for all)"
  type        = list(string)
  default     = ["*"]
}
