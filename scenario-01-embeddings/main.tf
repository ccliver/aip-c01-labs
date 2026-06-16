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
      Scenario = "01-embeddings"
    }
  }
}

# TODO: module "iam" — call modules/iam_roles for a Lambda execution role
# TODO: module "corpus_bucket" — call modules/s3 for embedding storage
# TODO: module "embedder_fn" — call modules/lambda_base with src/embedder/
# TODO: aws_bedrock_foundation_model_agreement — accept Titan Embeddings V2 EULA if required
