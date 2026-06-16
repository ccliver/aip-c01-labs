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
      Scenario = "03-advanced-retrieval"
    }
  }
}

# Prerequisite: scenario-01-embeddings must be deployed first.

# TODO: data "aws_bedrockagent_knowledge_base" — reference KB from scenario-02 by ID
# TODO: module "query_router_fn" — call modules/lambda_base; fn applies metadata filters
# TODO: module "iam" — call modules/iam_roles; add bedrock:Retrieve permissions
# TODO: aws_cloudwatch_log_group — capture full retrieval trace payloads
# Experiment areas:
# TODO: metadata filter expressions on the Retrieve API
# TODO: hybrid search configuration (vector + keyword)
# TODO: reranking with amazon.rerank-v1
