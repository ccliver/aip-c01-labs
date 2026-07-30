# aip-c01-labs

Lab curriculum for the AWS Certified AI Practitioner exam — see [README.md](./README.md)
for the scenario list, Taskfile usage, and shared Terraform modules.

## Before working in a scenario

Each `scenario-NN-*/README.md` documents that scenario's Goal, Infrastructure deployed,
Key concepts, and What to observe. Read the relevant scenario's README before making
changes there — don't assume structure or re-derive it from the Terraform alone.

## AWS API behavior: check docs before trial-and-error

When an AWS API (Bedrock, etc.) does something unexpected — a validation error, a
silent no-op, an enum that doesn't work as guessed — check AWS docs via the
`aws-documentation` MCP server (`search_documentation` / `read_documentation`) first,
before reverse-engineering the behavior empirically via CLI calls. It's usually faster
and the answer is often already written down. When docs give an example, notice what's
different about the example inputs, not just the outputs — a quiet pattern across
examples (e.g. every one using the same field value) can reveal an undocumented
constraint before you hit it as an error.

Known gotchas already confirmed against docs/live testing (don't re-derive these):

- `guardrailConfig.trace` (Converse API) is lowercase: `enabled` / `enabled_full` /
  `disabled` — not `ENABLED`. Documented in the Converse+guardrails guide.
- Bedrock Knowledge Bases silently skip ingesting any source file over 50MB
  (`MaximumFileSizeSupported: 52428800` bytes) — documented as a hard quota, but only
  surfaces at runtime via `aws bedrock-agent get-ingestion-job`'s `failureReasons`.
- `Converse`'s `modelId` accepts inference-profile IDs directly (e.g.
  `us.anthropic.claude-haiku-4-5-20251001-v1:0`) — no need to build a full ARN or look
  up an account ID via STS.
- `ApplyGuardrail`'s sensitive-information (PII) policy behaves as if it's only
  evaluated when `source="OUTPUT"` (confirmed empirically: `source="INPUT"` on
  identical PII text yields `sensitiveInformationPolicyUnits: 0`, i.e. not evaluated).
  This isn't stated explicitly in AWS docs, but every PII example in the
  `ApplyGuardrail` guide uses `source: "OUTPUT"`, including ones that read like user
  input — treat that pattern as a hint, not a guarantee, and re-verify if it matters.
  Comprehend's `detect_pii_entities` has no such quirk — it evaluates whatever text
  you hand it regardless of role, which is what makes it a useful complement in front
  of a guardrail rather than a redundant check (see `scripts/comprehend_guard.py`).
- The `aws_bedrock_guardrail` Terraform resource's `content_policy_config.filters_config`
  requires `output_strength` even when `output_enabled = false` — the provider schema
  lists it as optional, but `terraform apply` fails with "Missing required argument"
  if it's omitted. Set it to a valid enum value (e.g. `"NONE"`) rather than leaving it
  out, for filters like `PROMPT_ATTACK` that only apply to input.
- Amazon Titan Text Embeddings V2 on-demand quota is 6,000 requests/min and 300,000
  tokens/min per Region, and neither is adjustable. Useful ceiling to check before
  assuming a slow embedding pipeline is throttling-limited — do the RPM/TPM math
  first; the actual bottleneck is often self-imposed concurrency limits or sleeps,
  not the account quota.
- Comprehend's PII detection (`detect_pii_entities`) only supports English and
  Spanish `LanguageCode` values — don't wire in a dynamically detected language from
  `detect_dominant_language` without checking it's one of those two first.
- CloudTrail advanced event selectors: `eventSource` only supports `NotEquals` on a
  management-event selector (to exclude a noisy source like `kms.amazonaws.com`),
  never `Equals` to include just one — there's no way to scope a trail's management
  events down to Bedrock only. Confirmed via a live `InvalidEventSelectorsException`
  and the CloudTrail docs' only documented `eventSource` examples being exclusions.
- `ApplyGuardrail` is a CloudTrail **data** event (`AWS::Bedrock::Guardrail`), not a
  management event, despite looking like a normal Bedrock Runtime call. Its own docs
  page explicitly routes monitoring it to the data-events guide — don't assume it
  falls under "everything else defaults to management."
- CloudWatch Logs metric filter dimension values must be `$.field` selectors into the
  matched log event — a static label (e.g. `"Input"`/`"Output"`) is rejected with
  "dimension value must be valid selector." Encode a fixed distinction via separate
  metric names instead of a literal-valued dimension. Also: a metric filter rejects
  `default_value` once `dimensions` are set on the transformation.
- CloudWatch metric math `SEARCH()`'s `{Namespace,Dimension}` shorthand schema
  silently returns zero results (no error) for some real namespaces — confirmed for
  a custom namespace with a hyphen (`AIP-C01/Lab`) and a multi-segment AWS namespace
  (`AWS/Bedrock/Guardrails`), while working fine for `AWS/Bedrock`. The verbose
  `Namespace="..." MetricName="..."` predicate form works reliably in every case
  tested — prefer it, or explicit metric tuples, over the shorthand.
- Bedrock Prompt Management's `promptVariables` only supports a plain `{"text":
  ...}` value — no `guardContent`-tagged variant. A `guardrailConfig` attached to a
  Prompt-Management Converse call (`modelId=<prompt ARN>`) therefore evaluates the
  *entire* resolved template — including the developer's own instructional wrapper
  text — as unqualified input. This can false-positive the `PROMPT_ATTACK` content
  filter on a completely benign user question if the template's own phrasing (e.g.
  "return only JSON, no markdown") resembles a jailbreak pattern. Confirmed live via
  the guardrail trace. If the guardrail only matters for user-facing output, consider
  dropping `guardrailConfig` from internal steps like query expansion instead.
- Native `AWS/Bedrock` CloudWatch metrics' `ModelId` dimension resolves to the
  underlying foundation model actually invoked, even when the Converse call's
  `modelId` was a Prompt Management prompt ARN — there's no native way to track
  invocation counts per prompt or prompt version, only per underlying model.
