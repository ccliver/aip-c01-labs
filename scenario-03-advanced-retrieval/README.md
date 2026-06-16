# Scenario 03 — Advanced Retrieval

## Goal

Layer advanced retrieval patterns — metadata filtering, hybrid search, and reranking —
on top of the knowledge base built in scenario-02 to improve precision and relevance.

## Infrastructure deployed

| Resource | Purpose |
|---|---|
| Lambda (query router) | Wraps `bedrock-agent-runtime:Retrieve` with configurable filter expressions |
| CloudWatch Log Group | Captures full retrieval trace payloads for offline analysis |
| IAM additions | `bedrock:Retrieve` permission attached to the query execution role |

## Key concepts

- **Metadata filters** — restrict retrieval to document subsets using key/value attribute expressions; avoids cross-contaminating results from different document categories.
- **Hybrid search** — combines vector similarity with BM25 keyword matching; especially effective for exact-match queries (product codes, names) that embeddings handle poorly.
- **Reranking** — a second-pass model (Amazon Reranker) re-scores the top-k retrieved chunks by relevance to the query; improves precision without needing more chunks.
- **Number of results (k)** — increasing k improves recall but adds noise to the context window; tune based on your model's context limit and answer quality.
- **Score thresholds** — filter out low-confidence chunks before passing to the generative model.

## What to observe

1. Query with and without a metadata filter; compare the source documents returned.
2. Enable hybrid search and note score changes for short exact-keyword queries vs. longer semantic ones.
3. Enable reranking and observe how the chunk ordering changes relative to the raw vector score.
4. Log the full `retrievalResults` array and measure latency added by each additional retrieval step.

> **Dependency:** requires scenario-01-embeddings and scenario-02-knowledge-bases.
