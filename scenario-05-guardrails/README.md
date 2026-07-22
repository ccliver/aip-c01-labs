# Scenario 05 — Guardrails

## Goal

Configure Amazon Bedrock Guardrails to filter harmful content, detect and redact PII,
deny specific topic areas, and test boundary conditions against curated adversarial
inputs.

## Infrastructure deployed

| Resource | Purpose |
|---|---|
| Bedrock Guardrail | Enforces content filters, PII policy, topic denial, a custom word filter, and a contextual grounding check |
| Guardrail version | Immutable numbered snapshot for consistent production enforcement — auto-replaced whenever the guardrail's policy config changes |
| SSM Parameters | Publish the guardrail ID and pinned version so other scripts/scenarios can look them up at runtime |

`scripts/hybrid_search.py` (`--rerank`/`--query-expansion` with `--generate`) and
`scripts/kb_retrieve.py` read the guardrail ID/version from SSM and attach them to
their Bedrock `converse` calls. Both pass the retrieved chunk texts as a
`guardContent` block qualified `grounding_source`, alongside the question qualified
`query`, so the contextual grounding check can assess whether the generated answer
is actually supported by the retrieved context. `scripts/test_guardrails.py` drives the guardrail directly with
`bedrock-runtime:ApplyGuardrail` for the adversarial/PII/topic cases, and via a real
`converse` call (retrieving actual chunks from scenario-02, then generating a real
answer) for the grounding case, to exercise the same end-to-end path the two scripts
above use rather than a synthetic example.

## Key concepts

- **Content filters** — six categories (hate, insults, sexual, violence, misconduct, prompt attack) each with adjustable strength (NONE → LOW → MEDIUM → HIGH).
- **PII redaction** — detect named entity types (NAME, EMAIL, SSN, PHONE, etc.) and either BLOCK the request or ANONYMIZE by replacing with a placeholder.
- **Topic denial** — provide a natural-language description of topics the model must refuse; no keyword lists required.
- **Grounding check** — verify that the model's response is factually supported by the retrieved context; catches hallucinations.
- **Guardrail trace** — `assessments[].action` field shows `GUARDRAIL_INTERVENED` or `NONE` on every response; log it for audit.

## What to observe

Run `task scenario-05:test` (after `task scenario-05:up`, plus `task scenario-02:up`
for the grounding case) and inspect the output for each case:

1. A benign AWS question — `action` is `NONE`, response passes through unchanged.
2. A prompt matching the denied topic — `action` is `GUARDRAIL_INTERVENED` via `topicPolicy`.
3. Input containing a synthetic name/email/SSN — verify `ANONYMIZE` replaces them with placeholders in `outputs[].text`.
4. A prompt injection / jailbreak attempt — check whether it's caught (note: only the four listed content-filter categories are enabled here, not `PROMPT_ATTACK`, so some jailbreak phrasing may pass through untouched — a good discussion point on filter coverage).
5. A well-grounded question, answered from retrieved Step Functions user guide chunks — `stopReason` is not `guardrail_intervened` and the grounding score is high.
6. A question outside the retrieved context (same chunks, about AWS Systems Manager) — the model's answer strays from the source, the grounding score drops below `0.7`, and `stopReason` becomes `guardrail_intervened`.
7. Raise `content_filter_strength` to `HIGH` and re-test edge-case inputs.
