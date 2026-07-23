provider "opensearch" {
  url                   = var.opensearch_endpoint
  aws_region            = var.aws_region
  sign_aws_requests     = true
  aws_signature_service = "aoss"
  healthcheck           = false
}
