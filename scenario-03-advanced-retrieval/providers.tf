provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project  = var.project
      Scenario = "03-advanced-retrieval"
    }
  }
}
