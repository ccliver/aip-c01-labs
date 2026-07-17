# Scenario 06 — Governance

## Goal

Implement model access controls, invocation audit logging, and resource compliance
checks to build a governed Bedrock environment aligned with enterprise security and
responsible AI requirements.

## Infrastructure deployed

| Resource | Purpose |
|---|---|
| CloudTrail trail | Records all Bedrock management-plane API calls to S3 |
| S3 bucket (logs) | Durable storage for CloudTrail and invocation log data |
| IAM deny policy | Restricts `bedrock:InvokeModel` to an approved model allowlist |
| AWS Config rule | Flags Bedrock resources that are missing mandatory cost-allocation tags |

> **Note:** Data-plane invocation logging (request/response payloads to CloudWatch Logs + S3) is configured in `scenario-04-prompt-management`, not here. `aws_bedrock_model_invocation_logging_configuration` is an account+region-wide singleton, so only one scenario can manage it — scenario-04 must stay deployed for it to be active.

## Key concepts

- **Model access controls** — IAM condition key `bedrock:ModelId` limits which model ARNs a principal may invoke; combine with SCPs for account-wide enforcement.
- **CloudTrail for AI** — Bedrock management events (e.g., `CreateKnowledgeBase`) appear automatically; data events (`InvokeModel`) require explicit configuration and incur cost.
- **Invocation logging** — captures full prompt/completion payloads; useful for audit but sensitive — encrypt with KMS and restrict read access.
- **AWS Config** — managed rules for tagging compliance; combine with Conformance Packs for a broader control baseline.
- **Responsible AI governance** — data residency, model provenance, output accountability, and bias monitoring are all exam topics.

## What to observe

1. Attempt to call a non-approved model ID — observe the IAM `Deny` in the error response.
2. Open CloudTrail → Event History and filter on source `bedrock.amazonaws.com`.
3. Query invocation logs in CloudWatch Logs Insights for a specific request ID.
4. Tag a Bedrock resource without the required `Project` tag and watch Config flag the violation.
