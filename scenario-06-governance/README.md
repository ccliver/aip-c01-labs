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
  → Glue table "kb_corpus_chunks" (source_key, chunk_size, chunk_overlap,
    total_chunks, domain_tags, partitioned by ingestion_date) → Athena queries (optional)

CloudTrail trail (S3 delivery only)
  → Standard management events: InvokeModel, Converse (captured automatically)
  → Advanced event selectors (data events): Retrieve/RetrieveAndGenerate (KB),
    ApplyGuardrail + related Guardrails calls

Dashboard "aip-c01-governance" — mixed native + custom metric sources:
  → Token usage by model: native AWS/Bedrock (InputTokenCount/OutputTokenCount by ModelId)
  → Guardrails trigger rate: native AWS/Bedrock/Guardrails (InvocationsIntervened by GuardrailPolicyType)
  → PII detection events + chunking/retrieval stats (Scenarios 1-3): custom
    CloudWatch namespace "AIP-C01/Lab" (dimensions: Scenario + per-metric-type keys)
```

## Key Concepts

### Glue Data Catalog + Athena
Glue Data Catalog is a metastore, not a query engine — it's how Athena knows the schema of data
sitting in S3 so it can run SQL against it. The `invocation_logs` table and the `kb_corpus_chunks`
table are two separate catalog entries serving two different governance questions: what the model
did, versus what data fed it. Nothing in this lab automatically joins the two, but registering the
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
detection events. Rather than defaulting to custom metrics for all three, each was checked against
AWS-native CloudWatch metrics first: `AWS/Bedrock` already publishes `InputTokenCount`/
`OutputTokenCount` by `ModelId`, and `AWS/Bedrock/Guardrails` already publishes
`InvocationsIntervened` by `GuardrailPolicyType` — both for free, no code required. The dashboard's
"Token usage by model" and "Guardrails trigger rate" widgets read those native metrics directly,
filtered to the specific models/policies this lab uses. PII detection has no native equivalent (no
per-entity-type breakdown, and nothing for Comprehend's separate detection path, which is a
different service entirely), so it stays a custom metric.

This build also retroactively instrumented Scenarios 1-3 (chunking stats, retrieval hits) as custom
metrics — no native equivalent exists for these app-level RAG pipeline concepts. Both custom
metric types live under one namespace (`AIP-C01/Lab`, dimensions `Scenario` + per-metric-type
keys), so a future scenario can add new metric names/dimension combos here without restructuring
anything already emitting data — CloudWatch's (namespace, metric name, dimensions) model makes
that safe by construction.

**Lesson learned building this:** don't default to custom metrics just because a request describes
the mechanism as "custom" — check for a native equivalent first, and only build custom
instrumentation for the gap a native metric doesn't cover.

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
- Compare the `kb_corpus_chunks` table's fields against the `invocation_logs` table — confirm
  they're registering genuinely different things, not duplicate data
- In CloudTrail Event History, confirm `Retrieve`/`RetrieveAndGenerate` and `ApplyGuardrail` show
  up as data events, while `InvokeModel`/`Converse` show up as management events without any
  special trail config
- On the dashboard, confirm token usage and Guardrails trigger rate render from the native
  `AWS/Bedrock`/`AWS/Bedrock/Guardrails` namespaces, while PII detection events and the Scenario
  1-3 chunking/retrieval stats render from the custom `AIP-C01/Lab` namespace, filterable by the
  `Scenario` dimension
