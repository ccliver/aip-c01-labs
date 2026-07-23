data "terraform_remote_state" "scenario01" {
  backend = "local"
  config = {
    path = "${path.module}/../scenario-01-embeddings/terraform.tfstate"
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  kb_index_name       = "${var.project}-bedrock"
  corpus_bucket_name  = data.terraform_remote_state.scenario01.outputs.corpus_bucket_name
  collection_arn      = data.terraform_remote_state.scenario01.outputs.opensearch_collection_arn
  collection_endpoint = trimprefix(data.terraform_remote_state.scenario01.outputs.opensearch_collection_endpoint, "https://")
}

resource "aws_iam_role" "kb" {
  name = "${var.project}-kb-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "bedrock.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnLike = {
          "aws:SourceArn" = "arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:knowledge-base/*"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "kb" {
  name = "${var.project}-kb-policy"
  role = aws_iam_role.kb.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Read"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::${local.corpus_bucket_name}",
          "arn:aws:s3:::${local.corpus_bucket_name}/pdfs/*",
        ]
      },
      {
        Sid      = "BedrockEmbed"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = [var.embedding_model_arn]
      },
      {
        Sid      = "AOSSAccess"
        Effect   = "Allow"
        Action   = ["aoss:APIAccessAll"]
        Resource = [local.collection_arn]
      },
    ]
  })
}

# AOSS supports multiple data access policies per collection; this one grants the KB role access.
resource "aws_opensearchserverless_access_policy" "kb_data" {
  name = "${var.project}-kb-data"
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
    Principal = [aws_iam_role.kb.arn]
  }])
}

# Bedrock does not auto-create the AOSS index; it must exist with Bedrock's expected field names.
resource "opensearch_index" "kb" {
  name      = local.kb_index_name
  index_knn = true

  mappings = jsonencode({
    properties = {
      "bedrock-knowledge-base-default-vector" = {
        type      = "knn_vector"
        dimension = 1024
        method    = { name = "hnsw", engine = "faiss" }
      }
      "AMAZON_BEDROCK_TEXT_CHUNK" = { type = "text" }
      "AMAZON_BEDROCK_METADATA"   = { type = "text" }
    }
  })
}

resource "aws_bedrockagent_knowledge_base" "this" {
  name     = "${var.project}-kb"
  role_arn = aws_iam_role.kb.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = var.embedding_model_arn
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn    = local.collection_arn
      vector_index_name = local.kb_index_name
      field_mapping {
        vector_field   = "bedrock-knowledge-base-default-vector"
        text_field     = "AMAZON_BEDROCK_TEXT_CHUNK"
        metadata_field = "AMAZON_BEDROCK_METADATA"
      }
    }
  }

  depends_on = [
    aws_iam_role_policy.kb,
    aws_opensearchserverless_access_policy.kb_data,
    opensearch_index.kb,
  ]
}

resource "aws_bedrockagent_data_source" "pdfs" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.this.id
  name              = "${var.project}-pdfs"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn         = "arn:aws:s3:::${local.corpus_bucket_name}"
      inclusion_prefixes = ["pdfs/"]
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = var.chunking_strategy

      dynamic "fixed_size_chunking_configuration" {
        for_each = var.chunking_strategy == "FIXED_SIZE" ? [1] : []
        content {
          max_tokens         = var.max_tokens
          overlap_percentage = var.overlap_percentage
        }
      }
    }
  }
}

resource "null_resource" "kb_sync" {
  triggers = {
    knowledge_base_id = aws_bedrockagent_knowledge_base.this.id
    data_source_id    = aws_bedrockagent_data_source.pdfs.data_source_id
  }

  provisioner "local-exec" {
    command = "aws bedrock-agent start-ingestion-job --knowledge-base-id ${aws_bedrockagent_knowledge_base.this.id} --data-source-id ${aws_bedrockagent_data_source.pdfs.data_source_id} --region ${data.aws_region.current.name}"
  }
}
