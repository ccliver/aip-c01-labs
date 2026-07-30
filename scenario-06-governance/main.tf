# NOTE: aws_bedrock_model_invocation_logging_configuration is deployed by
# scenario-04-prompt-management, not here — it's an account+region-wide
# singleton, so only one scenario can own it. See its README for the CWL/S3
# destinations it configures. scenario-04 must stay deployed for data-plane
# invocation logging to be active in this account/region.

data "terraform_remote_state" "scenario04" {
  backend = "local"
  config = {
    path = "${path.module}/../scenario-04-prompt-management/terraform.tfstate"
  }
}

data "terraform_remote_state" "scenario01" {
  backend = "local"
  config = {
    path = "${path.module}/../scenario-01-embeddings/terraform.tfstate"
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  invocation_logs_bucket = data.terraform_remote_state.scenario04.outputs.bedrock_invocation_logs_bucket_name
  invocation_logs_prefix = data.terraform_remote_state.scenario04.outputs.bedrock_invocation_logs_prefix
  kb_corpus_bucket       = data.terraform_remote_state.scenario01.outputs.corpus_bucket_name
  kb_chunks_prefix       = "chunks/"
  cloudtrail_name        = "${var.project}-bedrock-trail"
  cloudtrail_arn         = "arn:aws:cloudtrail:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:trail/${local.cloudtrail_name}"
}

# CloudTrail management events (account-wide) + Bedrock KB/Guardrail data events
# ---
# InvokeModel/Converse/ApplyGuardrail-adjacent Bedrock calls default to
# management events, already covered below at no extra cost. Management events
# can't be scoped to one eventSource here (Equals isn't supported, only
# NotEquals for exclusions), so that selector is account-wide — filter to
# bedrock.amazonaws.com at query time instead. ApplyGuardrail itself is the
# exception: it's a data event under AWS::Bedrock::Guardrail, not management —
# both that and AWS::Bedrock::KnowledgeBase (Retrieve/RetrieveAndGenerate) get
# their own data-event selector below since those are the two data-event types
# this repo exercises.
resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket        = "${var.project}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}-cloudtrail"
  force_destroy = true
}

data "aws_iam_policy_document" "cloudtrail_logs_bucket" {
  statement {
    sid     = "AWSCloudTrailAclCheck"
    effect  = "Allow"
    actions = ["s3:GetBucketAcl"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    resources = [aws_s3_bucket.cloudtrail_logs.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.cloudtrail_arn]
    }
  }

  statement {
    sid     = "AWSCloudTrailWrite"
    effect  = "Allow"
    actions = ["s3:PutObject"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    resources = ["${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.cloudtrail_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  policy = data.aws_iam_policy_document.cloudtrail_logs_bucket.json
}

resource "aws_cloudtrail" "bedrock" {
  name                          = local.cloudtrail_name
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  include_global_service_events = false
  is_multi_region_trail         = false
  enable_log_file_validation    = true

  # CloudTrail only supports NotEquals on eventSource for management-event
  # selectors (to exclude noisy sources like KMS), not Equals to include just
  # one — there's no way to scope a trail's management events to Bedrock only.
  # This selector is account-wide for all management events; filter to Bedrock
  # at query time in CloudTrail Event History / Lake instead.
  advanced_event_selector {
    name = "All management events"

    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }

  advanced_event_selector {
    name = "Bedrock Knowledge Base data events"

    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }
    field_selector {
      field  = "resources.type"
      equals = ["AWS::Bedrock::KnowledgeBase"]
    }
  }

  # ApplyGuardrail is a data event under AWS::Bedrock::Guardrail, not a
  # management event — its own docs page says to look for it under data
  # events, not the general "everything else is management" rule.
  advanced_event_selector {
    name = "Bedrock Guardrail data events"

    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }
    field_selector {
      field  = "resources.type"
      equals = ["AWS::Bedrock::Guardrail"]
    }
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]
}

# ─── Athena over Bedrock Model Invocation Logs ────────────────────────────
# Athena scans every object under LOCATION regardless of "subfolder" depth
# (S3 keys are flat), so the prefix root is enough — no partitioning needed
# at lab scale. No latency field exists in this log schema (see README); real
# per-model latency lives only in the CloudWatch InvocationLatency metric.
# inputBodyJson/outputBodyJson are left undeclared since their shape varies by
# model and the JSON SerDe just ignores undeclared fields.
resource "aws_glue_catalog_database" "bedrock_logs" {
  name = "${replace(var.project, "-", "_")}_bedrock_logs"
}

resource "aws_glue_catalog_table" "invocation_logs" {
  name          = "invocation_logs"
  database_name = aws_glue_catalog_database.bedrock_logs.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    classification = "json"
  }

  storage_descriptor {
    location      = "s3://${local.invocation_logs_bucket}/${local.invocation_logs_prefix}"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
      parameters = {
        "ignore.malformed.json" = "true"
      }
    }

    columns {
      name = "schematype"
      type = "string"
    }
    columns {
      name = "requestid"
      type = "string"
    }
    columns {
      name = "timestamp"
      type = "string"
    }
    columns {
      name = "modelid"
      type = "string"
    }
    columns {
      name = "errorcode"
      type = "string"
    }
    columns {
      name = "input"
      type = "struct<inputcontenttype:string,inputtokencount:int>"
    }
    columns {
      name = "output"
      type = "struct<outputcontenttype:string,outputtokencount:int>"
    }
  }
}

resource "aws_s3_bucket" "athena_results" {
  bucket        = "${var.project}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}-athena-results"
  force_destroy = true
}

resource "aws_athena_workgroup" "bedrock_logs" {
  name          = "${var.project}-bedrock-logs"
  force_destroy = true

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = false

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.id}/query-results/"
    }
  }
}

# ─── Athena over the Scenario 1 KB corpus metadata ────────────────────────
# scenario-01's pdf_handler writes one chunks/ingestion_date=<date>/<stem>.json
# audit file per ingested PDF (chunk text lives inline in the SQS message to
# the embedder, not read back from this file — so restructuring its S3 key
# layout here doesn't affect anything downstream). Only source_key, the chunk
# count/sizing, and domain_tags actually exist in that payload; there's no
# per-request latency-style field here either, and the raw "chunks" text array
# is deliberately left undeclared to keep this table metadata-only.
#
# ingestion_date is a Hive-style partition via the S3 key (partition
# projection below computes locations formulaically — no crawler or MSCK
# REPAIR needed). domain_tags is a list, so it can't be a partition key
# (partition columns must be scalar) — it's a regular column. source_key is
# also a regular column: one distinct value per PDF makes it a poor partition
# key (partition-per-row defeats the purpose of partitioning).
resource "aws_glue_catalog_database" "kb_corpus" {
  name = "${replace(var.project, "-", "_")}_kb_corpus"
}

resource "aws_glue_catalog_table" "kb_corpus_chunks" {
  name          = "kb_corpus_chunks"
  database_name = aws_glue_catalog_database.kb_corpus.name
  table_type    = "EXTERNAL_TABLE"

  partition_keys {
    name = "ingestion_date"
    type = "string"
  }

  parameters = {
    classification                       = "json"
    "projection.enabled"                 = "true"
    "projection.ingestion_date.type"     = "date"
    "projection.ingestion_date.format"   = "yyyy-MM-dd"
    "projection.ingestion_date.range"    = "2024-01-01,NOW"
    "projection.ingestion_date.interval" = "1"
    "storage.location.template"          = "s3://${local.kb_corpus_bucket}/${local.kb_chunks_prefix}ingestion_date=$${ingestion_date}/"
  }

  storage_descriptor {
    location      = "s3://${local.kb_corpus_bucket}/${local.kb_chunks_prefix}"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
      parameters = {
        "ignore.malformed.json" = "true"
      }
    }

    columns {
      name = "source_key"
      type = "string"
    }
    columns {
      name = "chunk_size"
      type = "int"
    }
    columns {
      name = "chunk_overlap"
      type = "int"
    }
    columns {
      name = "total_chunks"
      type = "int"
    }
    columns {
      name = "domain_tags"
      type = "array<string>"
    }
  }
}
