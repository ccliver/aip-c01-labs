# Scenario 6 — AI Governance, Compliance & Audit Pipeline

## What This Scenario Builds

A queryable audit trail spanning three layers: a Glue Data Catalog + Athena setup over Bedrock
Model Invocation Logs (what the model did), a separate Glue table with lineage metadata over the
KB corpus in S3 (what data it's allowed to draw from), a CloudTrail trail with advanced event
selectors for the Bedrock operations that count as data events, and a CloudWatch dashboard rolling
up governance metrics across the whole lab so far.

## Architecture

```
Bedrock Model Invocation Logs (S3 + CWL, since Scenario 4)
  → Glue table "invocation_logs" → Athena queries

S3 KB Corpus (Scenario 1/2 documents)
  → Glue table "corpus_lineage" (source_key, chunk_size, chunk_overlap,
    total_chunks, ingestion_date, domain_tags) → Athena queries (optional)

CloudTrail trail (S3 delivery only)
  → Standard management events: InvokeModel, Converse (captured automatically)
  → Advanced event selectors (data events): Retrieve/RetrieveAndGenerate (KB),
    ApplyGuardrail + related Guardrails calls

CloudWatch namespace "AIP-C01/Lab" (dimensions: Scenario, MetricName)
  → Dashboard "aip-c01-governance": token usage by model, Guardrails trigger
    rate, PII detection events, chunking/retrieval stats from Scenarios 1-3
```

## Key Concepts

### Glue Data Catalog + Athena
Glue Data Catalog is a metastore, not a query engine — it's how Athena knows the schema of data
sitting in S3 so it can run SQL against it. The invocation-logs table and the corpus-lineage table
are two separate catalog entries serving two different governance questions: what the model did,
versus what data fed it. Nothing in this lab automatically joins the two, but registering the
corpus with lineage metadata (`ingestion_date`, `domain_tags`) is itself the governance artifact an
auditor wants to see, independent of whether a query ever touches it.

### Athena+Glue vs. CloudWatch Logs Insights
Logs Insights is for ad-hoc, recent-window investigation scoped to CloudWatch (used in Scenario 9
for hallucination-signal parsing) — fast, no setup, limited retention. Athena+Glue is for durable,
structured querying over long retention periods directly against S3 — cheaper at scale, supports
joins across sources, and gives a SQL interface to someone who isn't going to learn Logs Insights
syntax (e.g., a compliance auditor). Use case, not just tooling preference, decides which fits.

### CloudTrail: Management Events vs. Data Events
`InvokeModel` and `Converse` are CloudTrail **management events** — any standard trail captures
them with no extra config. The Bedrock operations that are genuine **data events**, requiring
advanced event selectors, are KB `Retrieve`/`RetrieveAndGenerate`, `InvokeAgent`, `InvokeFlow`, and
Guardrails calls (`ApplyGuardrail` and related). This is a common point of confusion and worth
memorizing directly — getting InvokeModel and Retrieve backwards is an easy trap on this exam.

### Governance Dashboard Scope
This scenario's required metrics are token usage by model, Guardrails trigger rate, and PII
detection events — all sourced from invocation logs. This build extended scope to also retroactively
instrument Scenarios 1-3 (chunking stats, retrieval hits) under a single namespace
(`AIP-C01/Lab`, dimensions `Scenario` + `MetricName`), specifically so Scenario 10 can add cache hit
rate, retrieval latency p50/p99, cost per query, and hallucination flag rate as new widgets without
restructuring anything.

## What the Exam Expects You to Know

- Model Invocation Logs are the primary forensic mechanism for FM interactions — capture request,
  response, token counts, latency; do not capture Guardrails' internal scoring
- CloudTrail covers the control plane; invocation logs cover the data plane
- InvokeModel/Converse are management events; KB retrieval, InvokeAgent, InvokeFlow, and Guardrails
  calls are data events requiring advanced event selectors
- Glue Data Catalog + Athena is the standard AWS pattern for SQL access over unstructured S3 log/
  document data — know it as a governance/compliance pattern, not deep Athena SQL or crawler config
- Data lineage means documenting what source data fed a KB/model, tagged with origin and ingestion
  metadata — a registered catalog entry counts as lineage documentation even without an automated
  consumer
- SageMaker Model Cards: awareness only, exam tests recognition not authoring

## What to Observe

- Query the invocation-logs Athena table and confirm you can filter by model ID, token counts,
  and timestamp
- Compare the corpus-lineage table's fields against the invocation-logs table — confirm they're
  registering genuinely different things, not duplicate data
- In CloudTrail Event History, confirm `Retrieve`/`RetrieveAndGenerate` and `ApplyGuardrail` show
  up as data events, while `InvokeModel`/`Converse` show up as management events without any
  special trail config
- On the dashboard, confirm metrics from Scenarios 1-3 (chunking, retrieval) and 4-6 (prompts,
  Guardrails, tokens) are all visible under the same namespace, filterable by the `Scenario`
  dimension
