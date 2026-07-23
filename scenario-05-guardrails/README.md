# Scenario 5 — Bedrock Guardrails + Defense-in-Depth Safety

## What This Scenario Builds

A multi-layer safety architecture around the RAG pipeline: Comprehend pre-processing to
filter input before it reaches the FM, Bedrock Guardrails enforcing policy at inference
time, and post-processing validation to flag low-confidence or ungrounded responses.

## Architecture

```
User Question
  → Comprehend Pre-processing (PII detection, sentiment, language)
      → Block if PII detected
      → Warn if negative sentiment or non-English
  → Hybrid Search (retrieve chunks from OpenSearch)
  → FM Invocation with Guardrails attached
      → Content filters (hate/violence/sexual/insults)
      → Denied topic enforcement
      → Word filters
      → PII masking on input and output
      → Prompt attack detection
      → Grounding check (response validated against retrieved chunks)
  → Post-processing Validation
      → Flag short responses (< 50 chars)
      → Flag uncertainty language
      → Flag responses not referencing retrieved chunks
      → Append disclaimer if any flag triggered
  → Response returned to user
```

## Key Concepts

### Defense-in-Depth
Defense-in-depth is a security principle where no single control point is sufficient —
you layer defenses so that if one layer is bypassed, another catches it. The analogy
to web development: Comprehend is like browser-side input validation (fast, cheap, catches
obvious problems early), Guardrails is server-side validation (authoritative, can't be
bypassed by sending requests directly), and post-processing is response sanitization
before returning to the client.

Each layer catches different threats at different points:
- **Comprehend**: catches PII, negative sentiment, and language issues before FM invocation
- **Guardrails**: enforces content policy and grounding at inference time
- **Post-processing**: catches structural/quality issues in FM output

### Bedrock Guardrails
Guardrails is attached per API call via `guardrailIdentifier` and `guardrailVersion`
parameters — it is not a global account setting. Store Guardrail ID and version in SSM
Parameter Store so all consumers read from one place without hardcoding.

**Filter types:**
- **Content filters**: strength settings (NONE/LOW/MEDIUM/HIGH) for hate, violence,
  sexual content, insults, misconduct — applied independently to input and output
- **Denied topics**: refuse to discuss defined topics regardless of how the question
  is framed
- **Word filters**: block specific terms or managed lists (profanity)
- **PII masking**: detect and ANONYMIZE or BLOCK PII entity types (NAME, EMAIL, PHONE,
  US_SSN, etc.) in input and output
- **Prompt attack**: detect and block prompt injection and jailbreak attempts
- **Grounding check**: validate FM response against provided source content

**What Guardrails does NOT capture:** internal scoring details are not in Model Invocation
Logs — only the intervention action and affected policy are logged.

### Grounding Check
The grounding check compares the FM's response against chunks you pass as `groundingSource`
in the API call. It scores how well the response is supported by that content (0-1). If
the score falls below your configured threshold the response is blocked.

This is the primary hallucination mitigation mechanism in the exam's mental model — if
the FM generates a claim not supported by the retrieved chunks, Guardrails catches it
before it reaches the user.

**Observed in lab:** well-grounded response scored 0.96 (passed), response about content
not in the corpus scored 0.1 (blocked).

### Amazon Comprehend Pre-processing
Comprehend API calls are significantly cheaper than Bedrock FM invocations. Using Comprehend
as a pre-filter catches obvious problems before spending money on an inference call.

**Capabilities used:**
- `detect_pii_entities()` — block requests containing PII before FM invocation
- `detect_sentiment()` — flag highly negative inputs (NEGATIVE with >0.9 confidence)
- `detect_dominant_language()` — warn if input is not English

Comprehend PII detection at the input stage is complementary to Guardrails PII masking —
Comprehend blocks the request entirely, Guardrails anonymizes and allows it through.

### Post-processing Validation
After FM response, before returning to user:
- **Length check**: responses under 50 characters likely indicate insufficient context
- **Uncertainty language**: phrases like "I don't know" or "I cannot find" signal the
  FM didn't have good grounding
- **Chunk reference check**: verify response references content from retrieved chunks —
  absence may indicate hallucination
- **Action**: append disclaimer rather than block — preserves user experience while
  flagging low confidence

## What the Exam Expects You to Know

- Defense-in-depth means layering controls — no single layer is sufficient
- Guardrails is opt-in per API call, not a global setting — use SSM for centralized config
- Content filter strength levels: NONE/LOW/MEDIUM/HIGH, applied independently to input/output
- Denied topics block regardless of phrasing — more robust than word filters
- PII masking ANONYMIZES (replaces with entity type placeholder) vs. BLOCK (rejects entirely)
- Prompt attack filter catches injection and jailbreak attempts
- Grounding check is the primary hallucination mitigation mechanism
- Comprehend is cheaper than FM inference — use it as a pre-filter for cost efficiency
- Guardrails does not capture internal scoring in Model Invocation Logs
- Post-processing catches structural issues Guardrails doesn't evaluate
- Know which layer catches which threat type for exam scenario questions

## What to Observe

- Run `test_guardrails.py` and verify each layer catches its intended threat:
  - Comprehend blocks PII before FM is ever called
  - Guardrails ANONYMIZES PII that makes it through (if Comprehend is bypassed)
  - Prompt attack filter catches injection and jailbreak attempts
  - Denied topic blocks off-topic questions
  - Grounding check blocks responses not supported by retrieved chunks
  - Post-processing appends disclaimer on short or uncertain responses
- Check CloudWatch Logs for Comprehend flags and post-processing warnings
- Check Model Invocation Logs in S3 to confirm Guardrails intervention action is captured
  but internal scoring is not
