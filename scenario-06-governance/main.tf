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
      Scenario = "06-governance"
    }
  }
}

# TODO: aws_cloudtrail — trail capturing all bedrock:* management events
# TODO: aws_s3_bucket + aws_s3_bucket_policy — CloudTrail log destination
# TODO: aws_iam_policy — deny bedrock:InvokeModel except for approved model IDs
# TODO: aws_config_rule — detect Bedrock resources missing required tags
# TODO: aws_bedrock_model_invocation_logging_configuration — enable data-plane logging
