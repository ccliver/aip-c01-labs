# Scenario 09 — Troubleshooting

## Goal

Reproduce, diagnose, and resolve common Amazon Bedrock and RAG pipeline failures
using CloudWatch Logs Insights, X-Ray traces, and AWS Service Quotas.

## Infrastructure deployed

| Resource | Purpose |
|---|---|
| Lambda (probe) | Deliberately triggers ThrottlingException, AccessDeniedException, and model errors |
| IAM role (under-scoped) | Intentionally missing permissions to reproduce AccessDeniedException |
| CloudWatch Log Group | Aggregates probe function invocation traces |
| CloudWatch Logs Insights query | Pre-built query filtering Bedrock errors by exception type |
| X-Ray group | Isolates Bedrock-related traces for latency root-cause analysis |

## Key concepts

- **ThrottlingException** — TPS or tokens-per-minute quota exceeded; fix with exponential back-off with jitter.
- **ModelTimeoutException** — request exceeded the 60-second streaming timeout; reduce context size or chunk the input.
- **AccessDeniedException** — missing IAM permission or model access not enabled in this region; always check both.
- **Hallucination detection** — grounding checks (scenario-05) and output comparison against retrieved citations are the primary mitigation strategies.
- **Quota increase workflow** — Service Quotas console → select Bedrock → request an increase → monitor with CloudWatch.

## What to observe

1. Invoke the probe Lambda in rapid succession; observe `ThrottlingException` appearing in CloudWatch logs.
2. Inspect the X-Ray trace waterfall to identify which downstream call introduced the most latency.
3. Run the saved Logs Insights query to aggregate error types and counts over the last hour.
4. Fix the under-scoped IAM policy and confirm the `AccessDeniedException` disappears on the next invocation.
5. Navigate to Service Quotas → Amazon Bedrock and identify the TPS and TPM limits for your chosen model.

> **Dependency:** requires scenario-01-embeddings to be deployed.
