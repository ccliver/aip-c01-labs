# Scenario 3 — Advanced Retrieval Patterns

## What This Scenario Builds

Advanced retrieval layers on top of the Scenario 1 OpenSearch index: hybrid search combining
BM25 keyword scoring with k-NN vector search, a Bedrock reranker call to reorder results by
true relevance, query expansion to broaden retrieval recall, and a Step Functions workflow
that orchestrates the full pipeline with parallel retrieval across query variants.

## Architecture

```
User Question
  → Step Functions State Machine
      → QueryExpansion (Bedrock SDK integration — Claude generates 3 query variants)
      → ParallelRetrieval (Map state — Lambda runs hybrid search for each variant)
          → Merge & Deduplicate by chunk_id (inside Lambda)
      → Rerank (Bedrock SDK integration — reranker model scores chunks against question)
  → Top-k reranked chunks returned
```

All retrieval runs against the existing OpenSearch Serverless index from Scenario 1.
No new vector store infrastructure is created in this scenario.

## Key Concepts

### Hybrid Search
Hybrid search combines two retrieval signals in a single OpenSearch query:

- **k-NN (vector search)**: finds chunks whose embedding vectors are closest to the query
  vector. Catches conceptual matches even when terminology differs.
- **BM25 (keyword search)**: scores chunks by term frequency and document frequency.
  Catches exact term matches that semantic search may miss.

OpenSearch's `hybrid` query type runs both simultaneously. A `normalization-processor`
search pipeline normalizes each score to a 0-1 range then combines them using configurable
weights (default 0.3 BM25 / 0.7 vector). The resulting hybrid score is not directly
comparable to a raw k-NN cosine similarity score — only compare hybrid scores against
other hybrid scores.

**When hybrid outperforms k-NN alone:** queries using informal or paraphrased language
where the relevant chunks use precise technical terminology. Semantic search finds the
concept; keyword search finds the exact term.

### Reranking
Reranking is a second FM inference call that reorders retrieved chunks by true relevance
to the question. Unlike embedding models which encode text independently, a reranker is
a cross-encoder that evaluates the question and each chunk together as a pair.

**Retrieval vs. relevance:** a chunk can score high on vector similarity but still not
directly answer the question. The reranker catches this — it scores how well a specific
chunk answers the specific question, not just how similar they are as vectors.

**Tradeoff:** reranking is slower and more expensive than retrieval since it's a separate
FM inference call per chunk. Use it when precision matters more than latency.

**Pattern:** hybrid search for recall → reranker for precision.

### Query Expansion
Query expansion sends the original question to an FM and asks it to generate rephrased
variants. All variants are run through retrieval and results are deduplicated by chunk_id
before reranking.

**Why it helps:** a poorly worded or informal query may miss relevant chunks that use
different terminology. Variants cover more of the semantic space and increase recall.

**Tradeoff:** more retrieval calls (4x in this scenario), more chunks to rerank, higher
latency and cost. Worth it when recall is more important than speed.

**Full pattern:** query expansion (recall) → hybrid search (recall) → reranking (precision).

### Step Functions Orchestration
The Map state runs hybrid search in parallel across all query variants rather than
sequentially. This is the same pattern used in document ingestion pipelines to process
pages in parallel — just applied to query variants instead.

Direct Bedrock SDK integrations handle the query expansion and reranking states without
Lambda wrappers. Only the OpenSearch hybrid search requires a Lambda since there is no
native Step Functions integration for OpenSearch.

**Exam pattern:** Step Functions + Map state + Bedrock SDK integrations for multi-stage
agentic and retrieval pipelines is a recurring exam topic. Know which states need Lambda
vs. which can use direct SDK integrations.

## What the Exam Expects You to Know

- Hybrid search combines BM25 and k-NN — when to use it vs. k-NN only
- BM25 scores keyword relevance; k-NN scores semantic similarity — they complement each other
- Reranking is a cross-encoder FM call — scores question/chunk pairs, not independent vectors
- Retrieval score ≠ relevance to question — reranking addresses this gap
- Query expansion improves recall; reranking improves precision
- The full pattern: query expansion → hybrid retrieval → rerank
- Step Functions Map state for parallel retrieval across query variants
- Direct Bedrock SDK integrations vs. Lambda wrappers — know when each is appropriate
- Latency and cost tradeoffs: each added layer (hybrid, reranking, expansion) adds cost

## What to Observe

- Run the same question through k-NN only vs. hybrid and compare result ordering,
  especially positions 2-5 — reordering signals hybrid is adding value
- Use informal or paraphrased phrasing ("how many lambdas can run at once") and observe
  whether hybrid surfaces better results than k-NN alone
- Compare hybrid results before and after reranking — does a lower-scored chunk move to
  the top because it better answers the question?
- Enable query expansion with a vague question and observe: how many unique chunks survive
  deduplication? Does the top reranked result differ from the top hybrid result?
- In Step Functions console, observe the Map state executing parallel branches and the
  execution timeline showing retrieval running concurrently across variants
