variable "bucket_suffix" {
  description = "Suffix appended to the bucket name (must produce a globally unique name)"
  type        = string
}

variable "project" {
  description = "Project tag propagated to the bucket"
  type        = string
}

variable "versioning_enabled" {
  description = "Enable S3 versioning"
  type        = bool
  default     = true
}
