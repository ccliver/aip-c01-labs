provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project  = var.project
      Scenario = "02-knowledge-bases"
    }
  }
}

# The collection already exists (deployed by scenario-01 before this scenario
# runs), so unlike scenario-01's index submodule, there's no chicken-and-egg
# problem configuring this provider directly in the root module.
provider "opensearch" {
  url                   = "https://${local.collection_endpoint}"
  aws_region            = var.aws_region
  sign_aws_requests     = true
  aws_signature_service = "aoss"
  healthcheck           = false
}
