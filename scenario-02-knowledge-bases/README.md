# Scenario 2 — Bedrock Knowledge Bases (Managed RAG)

## What This Scenario Builds

A Bedrock Knowledge Base pointed at the same S3 corpus from Scenario 1, using OpenSearch
Serverless as the backing vector store. Retrieval results are compared directly against the
DIY Lambda pipeline from Scenario 1 to understand the managed vs. DIY tradeoff.

## Architecture

```
S3 (same corpus bucket as Scenario 1)
  → Bedrock Knowledge Base (managed chunking + embedding + indexing)
  → OpenSearch Serverless (KB-managed index, separate from Scenario 1 index)
  → KB Retrieve API (query endpoint)
```

Scenario 1 and Scenario 2 use the same OpenSearch Serverless collection but different
indexes — Scenario 1 writes to its own index via Lambda, KB creates and manages its own.

## Key Concepts

### What a Knowledge Base Does
A Bedrock Knowledge Base is a fully managed RAG pipeline. It replaces the two-Lambda
architecture from Scenario 1 (ingestion + embedding) with a managed sync job that:

1. Reads documents from S3
2. Extracts text
3. Chunks using the configured strategy
4. Calls the configured embedding model (Titan or Cohere)
5. Writes vectors + chunk text to the backing vector store

You configure chunking strategy, embedding model, and vector store. Bedrock handles
everything else.

### Sync Jobs
KB does not automatically index documents on creation or on S3 upload. You must trigger
a sync job to ingest documents. Sync jobs can be:

- **On-demand**: triggered manually or via API/CLI
- **Scheduled**: periodic re-sync (useful for frequently updated corpora)
- **Incremental**: only processes new or changed documents since last sync

For automation, trigger sync via `aws bedrock-agent start-ingestion-job` in a
Terraform `null_resource` local-exec provisioner after KB creation.

### Chunking Options in KB
KB supports three chunking strategies configurable at setup time:

- **Fixed-size**: character or token count with overlap percentage
- **Hierarchical**: parent/child chunks — small chunks retrieved, parent returned to FM
- **Semantic**: splits on meaning boundaries using an FM call

### Metadata Filtering
KB supports metadata filtering on queries — you can restrict retrieval to documents
matching specific metadata fields (source, domain, date range). The metadata schema
must be defined when setting up the data source. This is useful for multi-tenant RAG
or domain-scoped retrieval.

### When to Use KB vs. DIY Pipeline

**Use KB when:**
- Documents update frequently and you want managed sync
- You want to avoid maintaining embedding Lambda infrastructure
- Titan or Cohere embedding models are sufficient
- Operational simplicity matters more than retrieval flexibility

**Use DIY pipeline when:**
- You need a custom or fine-tuned embedding model (e.g. SBERT on SageMaker)
- You need custom reranking logic
- Your data source isn't S3
- You need fine-grained control over chunking behavior

### Retrieval Quality vs. Similarity Scores
Higher similarity scores do not always mean better retrieval quality. In this scenario:

- Scenario 1 (1024 token chunks, 100 overlap) produced higher scores but less focused content
- Scenario 2 KB (300 token chunks, 10% overlap) produced lower or similar scores but
  more coherent, readable results

Smaller chunks match query terms more tightly (higher scores) but may lack surrounding
context. The right chunk size depends on the query type and FM context window usage.
Scores are a proximity measure, not a quality measure.

## What the Exam Expects You to Know

- KB abstracts chunking, embedding, and indexing into a managed sync job
- Sync must be triggered — it does not happen automatically on S3 upload
- KB supports fixed, hierarchical, and semantic chunking strategies
- Supported embedding models are Titan and Cohere — custom models require a DIY pipeline
- Metadata filtering enables domain-scoped or tenant-scoped retrieval
- KB tradeoff: operational simplicity vs. retrieval flexibility
- KB uses OpenSearch Serverless as its primary vector store backing option
- Similarity scores measure vector proximity, not answer quality

## What to Observe

- Trigger a sync job and monitor progress in the Bedrock console
- Query the KB retrieve API with the same questions used in Scenario 1 kNN queries
- Compare: are scores higher or lower than Scenario 1? Is the returned content more or
  less coherent?
- Confirm via OpenSearch that KB created its own separate index in the same collection
- Try metadata filtering on a query and verify results are scoped correctly
