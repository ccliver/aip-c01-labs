# Scenario 05 — Guardrails

## Goal

Configure Amazon Bedrock Guardrails to filter harmful content, detect and redact PII,
deny specific topic areas, and test boundary conditions with a probe Lambda function.

## Infrastructure deployed

| Resource | Purpose |
|---|---|
| Bedrock Guardrail | Enforces content filters, PII policy, topic denials, and word filters |
| Guardrail version | Immutable snapshot for consistent production enforcement |
| Lambda (test harness) | Sends curated adversarial and benign prompts to test boundaries |
| CloudWatch Log Group | Records per-invocation guardrail trace detail (intervened / not intervened) |

## Key concepts

- **Content filters** — six categories (hate, insults, sexual, violence, misconduct, prompt attack) each with adjustable strength (NONE → LOW → MEDIUM → HIGH).
- **PII redaction** — detect named entity types (NAME, EMAIL, SSN, PHONE, etc.) and either BLOCK the request or ANONYMIZE by replacing with a placeholder.
- **Topic denial** — provide a natural-language description of topics the model must refuse; no keyword lists required.
- **Grounding check** — verify that the model's response is factually supported by the retrieved context; catches hallucinations.
- **Guardrail trace** — `assessments[].action` field shows `GUARDRAIL_INTERVENED` or `NONE` on every response; log it for audit.

## What to observe

1. Submit a benign prompt — confirm `assessments[].topicPolicy.topics[*].action` shows `ALLOWED`.
2. Submit a prompt matching a denied topic — observe the `BLOCKED` action and the custom message returned to the caller.
3. Include a synthetic SSN in the input — verify whether `ANONYMIZE` replaces it in the model's output.
4. Raise the violence content filter to HIGH and re-test edge-case inputs.
5. Measure latency with and without the guardrail attached to the same `InvokeModel` call.
