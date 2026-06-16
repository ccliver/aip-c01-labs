# Scenario 02 — Knowledge Bases

## Goal

Build an Amazon Bedrock Knowledge Base backed by OpenSearch Serverless, ingest
documents from S3, and run `Retrieve` and `RetrieveAndGenerate` API calls to
understand the full managed RAG pipeline.

## Infrastructure deployed

| Resource | Purpose |
|---|---|
| S3 bucket (corpus) | Source document store for the knowledge base data source |
| OpenSearch Serverless collection | Managed vector store (AOSS) holding indexed embeddings |
| Bedrock Knowledge Base | Orchestrates chunking, embedding, indexing, and retrieval |
| IAM roles | Bedrock ↔ AOSS trust, and caller ↔ Bedrock retrieve permissions |

## Key concepts

- **Knowledge Base** — a fully managed RAG pipeline: chunk → embed → index → retrieve.
- **Chunking strategy** — fixed-size, hierarchical, or semantic splits directly affect retrieval quality and context window usage.
- **Data source sync** — `StartIngestionJob` re-processes documents when the corpus changes; re-syncing is not automatic.
- **Retrieve vs. RetrieveAndGenerate** — `Retrieve` returns raw chunks and scores; `RetrieveAndGenerate` also runs inference and returns citations.
- **OpenSearch Serverless (AOSS)** — the default vector store; alternatives include Pinecone, Redis, and Aurora pgvector.

## What to observe

1. Upload sample documents from `data/` to the corpus bucket, then start a manual ingestion job.
2. Query via `RetrieveAndGenerate` and inspect the `citations` array in the response.
3. Ask a question on a topic not covered in the corpus — observe the grounded "I don't know" response.
4. Change `chunking_strategy` to `HIERARCHICAL`, re-ingest, and compare retrieved chunk sizes and relevance scores.

> **Dependency:** requires scenario-01-embeddings to be deployed.
