data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── S3 ───────────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "corpus" {
  bucket           = "${var.project}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}-an"
  bucket_namespace = "account-regional"
  force_destroy    = true
}

resource "aws_s3_bucket_notification" "pdf_trigger" {
  bucket = aws_s3_bucket.corpus.id

  lambda_function {
    lambda_function_arn = module.pdf_handler.lambda_function_arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "pdfs/"
    filter_suffix       = ".pdf"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

# ── SQS ──────────────────────────────────────────────────────────────────────

resource "aws_sqs_queue" "chunks_dlq" {
  name = "${var.project}-chunks-dlq"
}

resource "aws_sqs_queue" "chunks" {
  name                       = "${var.project}-chunks"
  visibility_timeout_seconds = 300
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.chunks_dlq.arn
    maxReceiveCount     = 3
  })
}

# ── PDF handler Lambda ────────────────────────────────────────────────────────

module "pdf_handler" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 8.8"

  function_name = "${var.project}-pdf-handler"
  description   = "Extracts text from PDFs, chunks, stores to S3, queues for embedding"
  handler       = "handler.handler"
  runtime       = "python3.13"
  architectures = ["arm64"]

  source_path = [{
    path       = "${path.module}/app"
    uv_install = true
  }]

  timeout     = 300
  memory_size = 1024

  build_in_docker           = true
  docker_image              = "ghcr.io/astral-sh/uv:python3.13-bookworm-slim"
  docker_additional_options = ["--platform", "linux/arm64"]

  environment_variables = {
    POWERTOOLS_SERVICE_NAME = "${var.project}-pdf-handler"
    LOG_LEVEL               = "INFO"
    CHUNK_SIZE              = var.chunk_size
    CHUNK_OVERLAP           = var.chunk_overlap
    QUEUE_URL               = aws_sqs_queue.chunks.url
  }

  create_role              = true
  attach_policy_statements = true
  policy_statements = {
    list_bucket = {
      effect    = "Allow"
      actions   = ["s3:ListBucket"]
      resources = [aws_s3_bucket.corpus.arn]
    }
    s3_read = {
      effect    = "Allow"
      actions   = ["s3:GetObject"]
      resources = ["${aws_s3_bucket.corpus.arn}/pdfs/*"]
    }
    s3_write = {
      effect    = "Allow"
      actions   = ["s3:PutObject"]
      resources = ["${aws_s3_bucket.corpus.arn}/chunks/*"]
    }
    sqs_send = {
      effect    = "Allow"
      actions   = ["sqs:SendMessage"]
      resources = [aws_sqs_queue.chunks.arn]
    }
  }
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id   = "AllowS3Invoke"
  action         = "lambda:InvokeFunction"
  function_name  = module.pdf_handler.lambda_function_name
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.corpus.arn
  source_account = data.aws_caller_identity.current.account_id
}

module "chunk_embedder" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 8.8"

  function_name = "${var.project}-chunk-embedder"
  description   = "Reads chunk batches from SQS, generates Titan embeddings, indexes to OpenSearch"
  handler       = "handler.handler"
  runtime       = "python3.13"
  architectures = ["arm64"]

  source_path = [{
    path       = "${path.module}/app-embedder"
    uv_install = true
  }]

  timeout     = 120
  memory_size = 512

  build_in_docker           = true
  docker_image              = "ghcr.io/astral-sh/uv:python3.13-bookworm-slim"
  docker_additional_options = ["--platform", "linux/arm64"]

  event_source_mapping = {
    sqs = {
      event_source_arn = aws_sqs_queue.chunks.arn
      batch_size       = 1
    }
  }

  environment_variables = {
    POWERTOOLS_SERVICE_NAME = "${var.project}-chunk-embedder"
    LOG_LEVEL               = "INFO"
    EMBEDDING_MODEL_ID      = var.embedding_model_id
    OS_ENDPOINT             = trimprefix(aws_opensearchserverless_collection.vectors.collection_endpoint, "https://")
    OS_INDEX                = "${var.project}-chunks"
  }

  create_role              = true
  attach_policy_statements = true
  policy_statements = {
    sqs_consume = {
      effect    = "Allow"
      actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
      resources = [aws_sqs_queue.chunks.arn]
    }
    bedrock_invoke = {
      effect    = "Allow"
      actions   = ["bedrock:InvokeModel"]
      resources = ["arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/${var.embedding_model_id}"]
    }
    aoss_api = {
      effect    = "Allow"
      actions   = ["aoss:APIAccessAll"]
      resources = [aws_opensearchserverless_collection.vectors.arn]
    }
  }
}

resource "aws_opensearchserverless_security_policy" "encryption" {
  name = "${var.project}-enc"
  type = "encryption"
  policy = jsonencode({
    Rules = [{
      Resource     = ["collection/${var.project}"]
      ResourceType = "collection"
    }]
    AWSOwnedKey = true
  })
}

resource "aws_opensearchserverless_security_policy" "network" {
  name = "${var.project}-net"
  type = "network"
  policy = jsonencode([{
    Rules = [
      { Resource = ["collection/${var.project}"], ResourceType = "collection" },
      { Resource = ["collection/${var.project}"], ResourceType = "dashboard" },
    ]
    AllowFromPublic = true
  }])
}

resource "aws_opensearchserverless_access_policy" "data" {
  name = "${var.project}-data"
  type = "data"
  policy = jsonencode([{
    Rules = [
      {
        Resource     = ["collection/${var.project}"]
        ResourceType = "collection"
        Permission   = ["aoss:CreateCollectionItems", "aoss:DeleteCollectionItems", "aoss:UpdateCollectionItems", "aoss:DescribeCollectionItems"]
      },
      {
        Resource     = ["index/${var.project}/*"]
        ResourceType = "index"
        Permission   = ["aoss:CreateIndex", "aoss:DeleteIndex", "aoss:UpdateIndex", "aoss:DescribeIndex", "aoss:ReadDocument", "aoss:WriteDocument"]
      },
    ]
    Principal = [
      data.aws_caller_identity.current.arn,
      module.pdf_handler.lambda_role_arn,
      module.chunk_embedder.lambda_role_arn,
    ]
  }])
}

resource "aws_opensearchserverless_collection" "vectors" {
  name = var.project
  type = "VECTORSEARCH"

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
  ]
}
