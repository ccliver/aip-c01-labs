data "terraform_remote_state" "scenario01" {
  backend = "local"
  config  = { path = "${path.module}/../scenario-01-embeddings/terraform.tfstate" }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  collection_endpoint = trimprefix(
    data.terraform_remote_state.scenario01.outputs.opensearch_collection_endpoint, "https://")
  collection_arn = data.terraform_remote_state.scenario01.outputs.opensearch_collection_arn
  index_name     = data.terraform_remote_state.scenario01.outputs.opensearch_index_name
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.project}-s03-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
}

resource "aws_iam_role_policy" "lambda_exec" {
  name = "${var.project}-s03-lambda-policy"
  role = aws_iam_role.lambda_exec.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "BedrockInvoke"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = "*"
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

resource "aws_opensearchserverless_access_policy" "s03_data" {
  name = "${var.project}-s03-data"
  type = "data"

  policy = jsonencode([{
    Rules = [
      {
        Resource     = ["collection/${var.project}"]
        ResourceType = "collection"
        Permission   = ["aoss:DescribeCollectionItems"]
      },
      {
        Resource     = ["index/${var.project}/*"]
        ResourceType = "index"
        Permission   = ["aoss:CreateIndex", "aoss:UpdateIndex", "aoss:DescribeIndex", "aoss:ReadDocument", "aoss:WriteDocument"]
      },
    ]
    Principal = [aws_iam_role.lambda_exec.arn]
  }])
}

resource "aws_cloudwatch_log_group" "sfn" {
  name              = "/aws/states/${var.project}-rag-pipeline"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "hybrid_search" {
  name              = "/aws/lambda/${var.project}-s03-hybrid-search"
  retention_in_days = 14
}

module "hybrid_search" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 8.8"

  function_name = "${var.project}-s03-hybrid-search"
  handler       = "handler.lambda_handler"
  runtime       = "python3.13"
  architectures = ["arm64"]

  source_path = [{
    path             = "${path.module}/app/hybrid_search"
    pip_requirements = true
  }]

  timeout     = 60
  memory_size = 512

  build_in_docker           = true
  docker_image              = "public.ecr.aws/sam/build-python3.13"
  docker_additional_options = ["--platform", "linux/arm64"]

  environment_variables = {
    OS_ENDPOINT        = local.collection_endpoint
    OS_INDEX           = local.index_name
    EMBEDDING_MODEL_ID = var.embedding_model_id
    BM25_WEIGHT        = tostring(var.bm25_weight)
    KNN_WEIGHT         = tostring(var.knn_weight)
    TOP_K              = tostring(var.top_k)
  }

  create_role = false
  lambda_role = aws_iam_role.lambda_exec.arn

  use_existing_cloudwatch_log_group = true
  depends_on = [
    aws_cloudwatch_log_group.hybrid_search,
    aws_opensearchserverless_access_policy.s03_data,
  ]
}

resource "aws_iam_role" "sfn_exec" {
  name = "${var.project}-s03-sfn"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}

resource "aws_iam_role_policy" "sfn_exec" {
  name = "${var.project}-s03-sfn-policy"
  role = aws_iam_role.sfn_exec.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeLambda"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = [module.hybrid_search.lambda_function_arn]
      },
      {
        Sid      = "BedrockConverse"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel", "bedrock:Converse"]
        Resource = "*"
      },
      {
        Sid      = "BedrockRerank"
        Effect   = "Allow"
        Action   = ["bedrock:Rerank"]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutLogEvents",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups",
        ]
        Resource = "*"
      },
    ]
  })
}

locals {
  rerank_model_arn = "arn:aws:bedrock:${data.aws_region.current.region}::foundation-model/${var.rerank_model_id}"

  sfn_definition = jsonencode({
    Comment = "RAG pipeline: query expansion → parallel hybrid retrieval → merge → rerank"
    StartAt = "QueryExpansion"
    States = {
      QueryExpansion = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:bedrockruntime:converse"
        Parameters = {
          ModelId  = var.claude_model_id
          Messages = [
            {
              Role    = "user"
              Content = [{ "Text.$" = "States.Format('Generate 3 rephrased variants of this question for document retrieval. Return only a JSON array of 3 strings, no markdown.\n\nQuestion: {}', $.question)" }]
            },
            {
              Role    = "assistant"
              Content = [{ Text = "[" }]
            }
          ]
        }
        ResultSelector = {
          "variants_text.$" = "$.Output.Message.Content[0].Text"
        }
        ResultPath = "$.expansion"
        Next       = "ParseVariants"
      }

      ParseVariants = {
        Type = "Pass"
        Parameters = {
          "question.$" = "$.question"
          "variants.$" = "States.StringToJson(States.Format('[{}', $.expansion.variants_text))"
        }
        Next = "BuildQueryArray"
      }

      BuildQueryArray = {
        Type = "Pass"
        Parameters = {
          "question.$" = "$.question"
          "queries.$"  = "States.Array($.question, States.ArrayGetItem($.variants, 0), States.ArrayGetItem($.variants, 1), States.ArrayGetItem($.variants, 2))"
        }
        Next = "ParallelRetrieval"
      }

      ParallelRetrieval = {
        Type           = "Map"
        ItemsPath      = "$.queries"
        ItemSelector   = { "query.$" = "$$.Map.Item.Value" }
        MaxConcurrency = 4
        Iterator = {
          StartAt = "HybridSearch"
          States = {
            HybridSearch = {
              Type     = "Task"
              Resource = "arn:aws:states:::lambda:invoke"
              Parameters = {
                FunctionName = module.hybrid_search.lambda_function_arn
                "Payload.$"  = "$"
              }
              ResultSelector = { "results.$" = "$.Payload.results" }
              End            = true
            }
          }
        }
        ResultPath = "$.search_results"
        Next       = "MergeResults"
      }

      MergeResults = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = module.hybrid_search.lambda_function_arn
          Payload = {
            "question.$"     = "$.question"
            "results_sets.$" = "$.search_results"
          }
        }
        ResultSelector = {
          "question.$"   = "$.Payload.question"
          "candidates.$" = "$.Payload.candidates"
          "sources.$"    = "$.Payload.sources"
        }
        Next = "Rerank"
      }

      Rerank = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:bedrockagentruntime:rerank"
        Parameters = {
          RerankingConfiguration = {
            Type = "BEDROCK_RERANKING_MODEL"
            BedrockRerankingConfiguration = {
              NumberOfResults = var.top_k
              ModelConfiguration = {
                ModelArn = local.rerank_model_arn
              }
            }
          }
          "Sources.$" = "$.sources"
          Queries = [{
            Type = "TEXT"
            TextQuery = {
              "Text.$" = "$.question"
            }
          }]
        }
        ResultPath = "$.rerank"
        Next       = "ShapeOutput"
      }

      ShapeOutput = {
        Type = "Pass"
        Parameters = {
          "question.$"   = "$.question"
          "candidates.$" = "$.candidates"
          "reranked.$"   = "$.rerank.Results"
        }
        End = true
      }
    }
  })
}

resource "aws_sfn_state_machine" "pipeline" {
  name       = "${var.project}-rag-pipeline"
  role_arn   = aws_iam_role.sfn_exec.arn
  type       = "EXPRESS"
  definition = local.sfn_definition

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }
}
