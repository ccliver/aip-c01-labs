# Scenario 04 — Prompt Management

## Goal

Use Amazon Bedrock Prompt Management to author, version, and deploy reusable prompt
templates, then invoke them via alias from a Lambda function without hardcoding
prompt text in application code.

## Infrastructure deployed

| Resource | Purpose |
|---|---|
| Bedrock Prompt | Named, versioned template with `{{variable}}` placeholders |
| Bedrock Prompt Version | Immutable snapshot of the prompt used in production |
| Lambda function | Resolves the prompt alias and calls `bedrock:InvokeModel` |
| IAM role | `bedrock:GetPrompt` + `bedrock:InvokeModel` permissions |

## Key concepts

- **Prompt template variables** — `{{variable_name}}` placeholders filled at invocation time, keeping logic and wording separate.
- **Prompt versioning** — each `CreatePromptVersion` call creates an immutable snapshot; safe to roll back at any time.
- **Prompt aliases** — a named pointer to a specific version; update the alias to promote a new version with zero changes to calling code.
- **System vs. human turns** — structuring multi-turn templates correctly (system prompt first, then alternating human/assistant) is required for instruction-following models.
- **Inference configuration** — temperature, top-p, and max tokens can be baked into the prompt or overridden at call time.

## What to observe

1. Invoke the Lambda with different variable values; confirm the template is applied server-side and not duplicated in your code.
2. Create a v2 of the prompt with revised wording; deploy it via alias and compare output quality side-by-side.
3. Roll the alias back to v1 — confirm calling code requires zero changes.
4. Search CloudTrail for `bedrock:GetPrompt` events to see who retrieved which prompt version.
