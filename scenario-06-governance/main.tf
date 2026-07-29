# TODO: aws_cloudtrail — trail capturing all bedrock:* management events
# TODO: aws_s3_bucket + aws_s3_bucket_policy — CloudTrail log destination
# TODO: aws_iam_policy — deny bedrock:InvokeModel except for approved model IDs
# TODO: aws_config_rule — detect Bedrock resources missing required tags

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
}

# ─── Athena over Bedrock Model Invocation Logs ────────────────────────────
# Bedrock delivers one gzip-compressed, newline-delimited JSON file per
# invocation batch under <bucket>/<prefix>/AWSLogs/<account>/BedrockModelInvocationLogs/...
# Athena scans every object under the table's LOCATION prefix regardless of
# "subfolder" depth (S3 keys are flat), so pointing at the prefix root is enough —
# no partitioning needed for a lab-scale volume of logs.
#
# Only fields that actually appear in the log schema are declared below
# (confirmed against a live sample + AWS docs). Notably absent: any per-request
# latency field — Bedrock does not include one in this log format. Real per-model
# latency lives only in the separate AWS/Bedrock CloudWatch "InvocationLatency"
# metric, not in these files. inputBodyJson/outputBodyJson are deliberately left
# undeclared: their shape varies wildly by model (embedding vectors vs. chat
# messages), and the JSON SerDe silently ignores undeclared fields rather than
# erroring on the mismatch.
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
  name = "${var.project}-bedrock-logs"

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
