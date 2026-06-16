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
      Scenario = "04-prompt-management"
    }
  }
}

# TODO: aws_bedrockagent_prompt — create a versioned prompt template with variables
# TODO: aws_bedrockagent_prompt_version — pin a numbered release of the prompt
# TODO: module "invoke_fn" — call modules/lambda_base; fn calls InvokeModel with prompt alias
# TODO: module "iam" — call modules/iam_roles; add bedrock:GetPrompt + InvokeModel permissions
