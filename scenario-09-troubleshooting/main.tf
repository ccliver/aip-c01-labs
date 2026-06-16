terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project  = var.project
      Scenario = "09-troubleshooting"
    }
  }
}

# Prerequisite: scenario-01-embeddings must be deployed first.

# TODO: module "probe_fn" — call modules/lambda_base; deliberately triggers common error conditions
# TODO: module "iam_underscoped" — intentionally restricted role to demonstrate AccessDeniedException
# TODO: aws_cloudwatch_log_group — aggregation point for probe function traces
# TODO: aws_cloudwatch_query_definition — saved Logs Insights queries for throttle/error analysis
# TODO: aws_xray_group — X-Ray group filtering Bedrock-related traces
