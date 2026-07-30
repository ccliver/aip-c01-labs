# Scenario 06 — Governance

## Goal

Implement model access controls, invocation audit logging, and resource compliance
checks to build a governed Bedrock environment aligned with enterprise security and
responsible AI requirements.

## Infrastructure deployed

| Resource | Purpose |
|---|---|
| CloudTrail trail | Records all account management events (CloudTrail can't scope management events to one source — see note below) plus `AWS::Bedrock::KnowledgeBase` and `AWS::Bedrock::Guardrail` data events, to S3 |
| S3 bucket (CloudTrail logs) | Durable storage for the trail; `force_destroy = true` wipes all delivered logs on `terraform destroy` |
| IAM deny policy | Restricts `bedrock:InvokeModel` to an approved model allowlist |
| AWS Config rule | Flags Bedrock resources that are missing mandatory cost-allocation tags |
| Glue Data Catalog database + table (`invocation_logs`) | Schema mapped over scenario-04's Bedrock invocation logs in S3, for SQL querying via Athena |
| Glue Data Catalog database + table (`kb_corpus_chunks`) | Schema mapped over scenario-01's KB corpus chunk metadata (`source_key`, `chunk_size`, `chunk_overlap`, `total_chunks`, `domain_tags`), partitioned by `ingestion_date` via Athena partition projection |
| Athena workgroup + S3 bucket (results) | Runs ad-hoc SQL against either Glue table; results land in a dedicated S3 prefix |

> **Note:** Data-plane invocation logging (request/response payloads to CloudWatch Logs + S3) is configured in `scenario-04-prompt-management`, not here. `aws_bedrock_model_invocation_logging_configuration` is an account+region-wide singleton, so only one scenario can manage it — scenario-04 must stay deployed for it to be active. This scenario's Glue tables build their S3 locations from scenario-01's/scenario-04's outputs rather than hardcoded paths.

## Key concepts

- **Model access controls** — IAM condition key `bedrock:ModelId` limits which model ARNs a principal may invoke; combine with SCPs for account-wide enforcement.
- **CloudTrail management vs. data events for Bedrock** — `InvokeModel`, `InvokeModelWithResponseStream`, `Converse`, and `ConverseStream` are explicitly documented as CloudTrail **management** events; every other Bedrock API operation defaults to management too — *except* the specific set called out as data events: `Retrieve`/`RetrieveAndGenerate` (`AWS::Bedrock::KnowledgeBase`, used by scenario-02), `ApplyGuardrail` (`AWS::Bedrock::Guardrail`, used by scenario-05 — its own docs page says to look for it under data events, not the general rule), `InvokeAgent` (`AWS::Bedrock::AgentAlias`), and `InvokeFlow` (`AWS::Bedrock::FlowAlias`). A trail can use basic *or* advanced event selectors, never both — this trail expresses management events as an advanced selector too (`eventCategory=Management`) so it can combine with the two data-event selectors on one trail.
- **CloudTrail can't scope management events to one source** — a natural instinct is to add an `eventSource=bedrock.amazonaws.com` field selector alongside `eventCategory=Management` to keep the trail Bedrock-only. The API rejects it (`InvalidEventSelectorsException`): `eventSource` only supports `NotEquals` for management-event selectors (used to *exclude* a noisy source like `kms.amazonaws.com`), not `Equals` to *include* just one. A trail's management events are inherently account-wide; the only narrowing available is filtering at query time in CloudTrail Event History or CloudTrail Lake.
- **Invocation logging** — captures full prompt/completion payloads; useful for audit but sensitive — encrypt with KMS and restrict read access.
- **AWS Config** — managed rules for tagging compliance; combine with Conformance Packs for a broader control baseline.
- **Responsible AI governance** — data residency, model provenance, output accountability, and bias monitoring are all exam topics.
- **Athena + Glue over invocation logs** — Athena is serverless SQL over data in S3; Glue Data Catalog supplies the schema (database/table) so Athena knows how to parse it. No ETL or servers to manage — a common pattern for ad-hoc analysis over log data that's too unstructured/high-volume for CloudWatch Logs Insights alone.
- **What the invocation log schema does *not* have** — no per-request latency field. Bedrock's model invocation log entries (`schemaType: "ModelInvocationLog"`) carry `input.inputTokenCount` / `output.outputTokenCount`, `modelId`, `requestId`, `timestamp`, and `errorCode` on failures — but nothing timing-related. Real per-model latency lives only in the separate `AWS/Bedrock` CloudWatch `InvocationLatency` metric, not in these log files.
- **Partition projection over Hive-style partitioning** — the `kb_corpus_chunks` table computes its `ingestion_date` partition locations formulaically instead of tracking a partition list in the Glue metastore, so new days show up automatically with no crawler or `MSCK REPAIR TABLE` step.

## What to observe

1. Attempt to call a non-approved model ID — observe the IAM `Deny` in the error response.
2. Open CloudTrail → Event History and filter on source `bedrock.amazonaws.com` — note `InvokeModel`/`Converse` calls appear as `Management` events with no extra setup. Event History only supports management events, so this view can never show the two data-event types below, no matter how the trail is configured.
3. Run a retrieval via scenario-02 (`task scenario-02:retrieve`) and a guardrail probe via scenario-05 (`task scenario-05:test`), then find the corresponding `Retrieve`/`ApplyGuardrail` `Data` events using `task scenario-06:trail-tail` (reads the trail's S3-delivered logs directly, since Event History can't show them).
4. Query invocation logs in CloudWatch Logs Insights for a specific request ID.
5. Tag a Bedrock resource without the required `Project` tag and watch Config flag the violation.
6. Run `task scenario-06:query` and compare invocation counts, error counts, and average token counts across models — driven entirely from real invocation log data in S3, not CloudWatch.
7. `terraform destroy` scenario-06 and confirm the CloudTrail S3 bucket is gone rather than left behind with orphaned logs.
