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
      Scenario = "02-knowledge-bases"
    }
  }
}

# Prerequisite: scenario-01-embeddings must be deployed first.

# TODO: module "corpus_bucket" — call modules/s3 for the RAG document corpus
# TODO: aws_opensearchserverless_collection — vector store for the knowledge base
# TODO: aws_opensearchserverless_access_policy
# TODO: aws_opensearchserverless_security_policy (network + encryption)
# TODO: aws_bedrockagent_knowledge_base
# TODO: aws_bedrockagent_data_source — points at the S3 corpus bucket
# TODO: module "iam" — call modules/iam_roles; add bedrock:Retrieve* permissions
