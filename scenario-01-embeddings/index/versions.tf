terraform {
  required_version = ">= 1.15"
  required_providers {
    opensearch = {
      source  = "opensearch-project/opensearch"
      version = "~> 2.3"
    }
  }
}
