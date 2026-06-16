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
      Scenario = "05-guardrails"
    }
  }
}

# TODO: aws_bedrock_guardrail — configure content filters, PII redaction, topic denial
# TODO: aws_bedrock_guardrail_version — pin a numbered version for production
# TODO: module "test_fn" — call modules/lambda_base; fn sends prompts through the guardrail
# TODO: module "iam" — call modules/iam_roles; add bedrock:ApplyGuardrail + InvokeModel
# TODO: aws_cloudwatch_log_group — capture guardrail trace events
