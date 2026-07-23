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
