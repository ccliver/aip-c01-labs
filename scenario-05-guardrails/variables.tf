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

variable "content_filter_strength" {
  description = "Strength (NONE | LOW | MEDIUM | HIGH) for the hate, violence, sexual, and insults content filters, applied to both input and output"
  type        = string
  default     = "MEDIUM"
}

variable "denied_topic_name" {
  description = "Name of the denied topic policy"
  type        = string
  default     = "off-topic"
}

variable "denied_topic_definition" {
  description = "Natural-language definition of the topic the guardrail should refuse to engage with"
  type        = string
  default     = "Provide information unrelated to AWS services"
}

variable "denied_topic_examples" {
  description = "Example phrases that should match the denied topic — sharpens the classifier's boundary and reduces false positives on legitimate AWS content"
  type        = list(string)
  default = [
    "What's your favorite movie?",
    "Can you write me a poem about love?",
    "What do you think about the upcoming election?",
    "Give me a recipe for chocolate chip cookies.",
  ]
}

variable "blocked_words" {
  description = "Custom word filter — exact-match terms blocked in both input and output"
  type        = list(string)
  default     = ["hackthesystem", "bypasssecurity", "sudo-override"]
}

variable "pii_entity_types" {
  description = "Managed PII entity types to detect and mask in both input and output"
  type        = list(string)
  default     = ["NAME", "EMAIL", "PHONE", "US_SOCIAL_SECURITY_NUMBER"]
}

variable "pii_action" {
  description = "Action for PII detection: BLOCK | ANONYMIZE"
  type        = string
  default     = "ANONYMIZE"
}

variable "grounding_threshold" {
  description = "Minimum contextual grounding score (0-1); responses scoring below this are blocked as insufficiently grounded in the supplied source content"
  type        = number
  default     = 0.7
}
