data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# NOTE: the AWS provider has no aws_bedrockagent_prompt_version or alias
# resource implemented as of v6.5. This resource's ARN always
# points at the mutable DRAFT.
resource "aws_bedrockagent_prompt" "query_expansion" {
  name            = "${var.project}-query-expansion"
  description     = "Generates rephrased variants of a retrieval question for hybrid search query expansion"
  default_variant = "default"

  variant {
    name          = "default"
    template_type = "CHAT"
    model_id      = var.foundation_model_id

    template_configuration {
      chat {
        input_variable {
          name = "question"
        }

        message {
          role = "user"
          content {
            text = "Generate 3 rephrased variants of the following question to help retrieve different but relevant document chunks. Return only a JSON array of 3 strings, no markdown.\n\nQuestion: {{question}}"
          }
        }

        message {
          role = "assistant"
          content {
            text = "[" # Prefill trick to for JSON output
          }
        }
      }
    }
  }
}

resource "aws_dynamodb_table" "prompt_registry" {
  name         = "${var.project}-prompt-registry"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "prompt_id"

  attribute {
    name = "prompt_id"
    type = "S"
  }
}

# Seeds the active version for query-expansion. active_version_arn points at
# the mutable DRAFT (see note above). Edit this row directly (console or
# `aws dynamodb put-item`) to simulate promoting a new version — Terraform
# won't revert it since item changes are ignored below.
resource "aws_dynamodb_table_item" "query_expansion_active" {
  table_name = aws_dynamodb_table.prompt_registry.name
  hash_key   = aws_dynamodb_table.prompt_registry.hash_key

  item = jsonencode({
    prompt_id          = { S = "query-expansion" }
    active_version_arn = { S = aws_bedrockagent_prompt.query_expansion.arn }
    status             = { S = "approved" }
  })

  lifecycle {
    ignore_changes = [item]
  }
}

# ─── Model invocation logging (CloudWatch Logs + S3) ──────────────────────
# This is an account+region-wide singleton — only one scenario in this repo
# may manage it. See scenario-06-governance's README for the cross-scenario note.

resource "aws_cloudwatch_log_group" "bedrock_invocation" {
  name              = "/aws/bedrock/model-invocations"
  retention_in_days = 14
}

resource "aws_s3_bucket" "bedrock_invocation_logs" {
  bucket        = "${var.project}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}-bedrock-logs"
  force_destroy = true
}

data "aws_iam_policy_document" "bedrock_invocation_logs_bucket" {
  statement {
    sid     = "AllowBedrockLogDelivery"
    effect  = "Allow"
    actions = ["s3:PutObject"]

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }

    resources = ["${aws_s3_bucket.bedrock_invocation_logs.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:bedrock:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }
}

resource "aws_s3_bucket_policy" "bedrock_invocation_logs" {
  bucket = aws_s3_bucket.bedrock_invocation_logs.id
  policy = data.aws_iam_policy_document.bedrock_invocation_logs_bucket.json
}

resource "aws_iam_role" "bedrock_logging" {
  name = "${var.project}-bedrock-logging"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "bedrock.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:aws:bedrock:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*" }
      }
    }]
  })
}

resource "aws_iam_role_policy" "bedrock_logging" {
  name = "${var.project}-bedrock-logging-policy"
  role = aws_iam_role.bedrock_logging.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "CloudWatchLogsDelivery"
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = ["${aws_cloudwatch_log_group.bedrock_invocation.arn}:*"]
    }]
  })
}

resource "aws_bedrock_model_invocation_logging_configuration" "this" {
  logging_config {
    text_data_delivery_enabled = true

    cloudwatch_config {
      log_group_name = aws_cloudwatch_log_group.bedrock_invocation.name
      role_arn       = aws_iam_role.bedrock_logging.arn
    }

    s3_config {
      bucket_name = aws_s3_bucket.bedrock_invocation_logs.id
      key_prefix  = "invocation-logs/"
    }
  }

  depends_on = [
    aws_iam_role_policy.bedrock_logging,
    aws_s3_bucket_policy.bedrock_invocation_logs,
  ]
}
