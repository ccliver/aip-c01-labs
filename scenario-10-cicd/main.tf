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
      Scenario = "10-cicd"
    }
  }
}

# TODO: module "artifact_bucket" — call modules/s3 for CodePipeline artifacts
# TODO: aws_iam_role — CodePipeline and CodeBuild service roles
# TODO: aws_codebuild_project — runs terraform plan/apply and Bedrock evaluation checks
# TODO: aws_codepipeline — Source → Build → Evaluate → Deploy stages
# TODO: aws_codestarconnections_connection — GitHub source connection
# TODO: aws_sns_topic — pipeline failure notifications
