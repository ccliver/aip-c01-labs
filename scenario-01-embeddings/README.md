# Scenario 01 — Embeddings

## Goal

Generate text embeddings via Amazon Bedrock Titan Embeddings V2 and store them in S3,
forming the foundation for downstream RAG scenarios (02, 03, 09).

## Infrastructure deployed

| Resource | Purpose |
|---|---|
| S3 bucket | Stores serialised embedding vectors alongside source documents |
| IAM role | Grants Lambda permission to call `bedrock:InvokeModel` |
| Lambda function | Reads a document from S3, calls Titan Embeddings V2, writes output JSON back to S3 |

## Key concepts

- **Embeddings** — dense numeric vectors that encode the semantic meaning of text.
- **Amazon Titan Embeddings V2** — AWS-native embedding model; supports up to 1,024-dimensional output with optional normalisation.
- **Dimensionality** — higher dimensions capture more nuance but increase storage and query cost.
- **Cosine similarity** — the standard distance metric for comparing embedding vectors; measures the angle between them, not their magnitude.
- **Embedding vs. generative models** — embedding models output a vector, not text; they are not invoked via `Converse` but via `InvokeModel` with a model-specific body.

## What to observe

1. Invoke the Lambda via the AWS console or CLI and inspect the output JSON in S3.
2. Compare cosine similarity scores between semantically related sentences vs. unrelated ones.
3. Check CloudWatch logs for the token count and latency on each invocation — these drive cost.
4. Experiment with the `dimensions` and `normalize` parameters in the Titan Embeddings V2 API and observe how the output vector changes.
