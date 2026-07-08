# Scenario 1 — Embeddings & Vector Store Fundamentals

## What This Scenario Builds

An end-to-end document ingestion pipeline that takes PDF files from S3, extracts and chunks
the text, generates vector embeddings, and indexes them in OpenSearch Serverless for semantic
search.

## Pipeline Architecture

```
S3 (PDF upload)
  → S3 Event Notification
  → Ingestion Lambda (PyMuPDF text extraction + LangChain chunking)
  → SQS (one message per chunk)
  → Embedding Lambda (Titan Embeddings v2 API call)
  → OpenSearch Serverless (vector index)
```

## Key Concepts

### Chunking
Chunking splits a document into smaller pieces before embedding. The size and overlap of
chunks directly affects retrieval quality — this matters more than embedding model choice
in most cases.

- **Fixed-size chunking**: splits on character or token count with a configurable overlap.
  Simple and fast but can split ideas awkwardly mid-sentence.
- **Hierarchical chunking**: parent/child relationship where small chunks are retrieved for
  precision but the parent chunk is passed to the FM for context. Better coherence than
  fixed-size.
- **Semantic chunking**: splits on meaning boundaries rather than arbitrary counts. Most
  accurate but more expensive to compute.

**Overlap** means the last N tokens of chunk N are repeated as the first N tokens of chunk
N+1. This prevents ideas that span a chunk boundary from being lost entirely.

**Watch out for:** Table of contents pages and index pages produce low-signal chunks that
score highly on generic queries and pollute retrieval results. Filter these out in production.

**LangChain class used:** `RecursiveCharacterTextSplitter` — splits on character count by
default. Use `from_tiktoken_encoder` for true token-based splitting.

### Embeddings
An embedding is a list of floating point numbers (a vector) that represents the semantic
meaning of a chunk of text. Two chunks about similar topics will produce similar vectors
even if they use completely different words.

**Chunking and embedding are sequential, not synonymous:**
1. Chunk the document (split into pieces)
2. Call Titan Embeddings API on each chunk (convert text → vector)
3. Index the vector + original text in OpenSearch (store for retrieval)

**Titan Embeddings v2** supports 256, 512, and 1024 dimensions. Use 1024 for best semantic
accuracy. The model ID is `amazon.titan-embed-text-v2:0`.

At Healthfirst, SBERT running on a SageMaker endpoint is used instead of Titan. SBERT
produces better semantic similarity for domain-specific text and allows fine-tuning on
healthcare data. Titan is fully managed but locked to Amazon's model weights.

### Vector Stores
A vector store is a database optimized for similarity search on embedding vectors. It stores
both the vector (for search) and the original chunk text (to return to the FM as context).

**OpenSearch Serverless** uses k-NN (k-Nearest Neighbors) search — find the k most similar
vectors to a query vector. Good fit for AWS-native RAG stacks and what Bedrock Knowledge
Bases uses under the hood.

**pgvector** (Aurora PostgreSQL extension) uses cosine similarity via SQL. More familiar
query interface but less flexible than OpenSearch's search DSL. The exam doesn't test
pgvector deeply — OpenSearch is the primary vector store in AWS reference architectures.

### k-NN Search
k-NN search converts a user's question into a vector using the same embedding model, then
finds the k stored chunks whose vectors are most numerically similar. Those chunks are
returned as context to the FM to generate an answer.

Low similarity scores (below ~0.5) indicate either the relevant content isn't indexed or
chunking is splitting the relevant section across chunk boundaries.

### SQS Fan-out
Large documents can produce thousands of chunks. Calling Titan sequentially in a single
Lambda would hit timeout limits. The solution is fan-out: the ingestion Lambda writes one
SQS message per chunk, and a separate embedding Lambda consumes the queue with high
concurrency. This mirrors the Healthfirst pipeline architecture.

## What the Exam Expects You to Know

- Chunking strategy tradeoffs: fixed-size vs. hierarchical vs. semantic
- Why overlap exists and what happens without it
- Chunking vs. embedding vs. indexing are three distinct sequential steps
- Titan Embeddings v2 dimensionality options and when to use each
- k-NN and cosine similarity are retrieval mechanisms, not ML training concepts
- OpenSearch Serverless vs. pgvector tradeoff: flexible search DSL vs. SQL interface
- SQS fan-out pattern for high-volume embedding workloads
- TOC chunks introduce retrieval noise — pre-filter low-signal content

## What to Observe

- Compare chunk text in CloudWatch logs: verify overlap is working by checking that the
  last N tokens of one chunk appear at the start of the next
- Query OpenSearch with `match_all` to confirm documents are indexed with embedding,
  text, chunk_id, source_key, timestamp, and domain fields
- Run kNN queries and observe: do results come from the expected source PDF? Are scores
  above 0.5? Are TOC chunks appearing at the top?
- Try generic questions ("What is Amazon Bedrock?") vs. specific questions ("What
  foundation models does Amazon Bedrock support?") and compare score distributions
