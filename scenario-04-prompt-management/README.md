# Scenario 4 — Prompt Management & Flows

## What This Scenario Builds

A governed prompt system using Bedrock Prompt Management with versioned templates stored
in DynamoDB for active version tracking, Bedrock Model Invocation Logging to S3 and
CloudWatch Logs for audit trail, and a basic Bedrock Prompt Flow demonstrating conditional
branching.

## Architecture

```
Hybrid Search Script
  → DynamoDB (read active prompt version ARN)
  → Bedrock Prompt Management (invoke versioned template with parameters)
  → FM (Claude/Titan generates response)

Bedrock Model Invocation Logs
  → S3 (long-term retention, queryable via Athena in Scenario 6)
  → CloudWatch Logs (real-time debugging, Logs Insights queries)
```

## Key Concepts

### Bedrock Prompt Management
Prompt Management externalizes FM prompts from application code into versioned, parameterized
templates stored in Bedrock. Instead of a hardcoded prompt string in your Lambda or script,
you reference a template by ARN and pass parameters at invocation time.

**Why it matters:** In teams with multiple people iterating on prompts, hardcoded strings
create drift, version conflicts, and no audit trail. Prompt Management gives you versioning,
rollback, and consistent parameterization across all consumers of a prompt.

**Version ARNs** follow the format:
`arn:aws:bedrock:region:account-id:prompt/prompt-id:version-number`

Note: As of this lab, the Terraform AWS provider does not support Prompt Versions —
version management is done via console or AWS CLI.

### Active Version Governance via DynamoDB
Bedrock Prompt Management has no built-in promotion or approval workflow — which version
your application uses is entirely your responsibility. The pattern used here:

- DynamoDB stores `{prompt_id, active_version_arn, status}` per template
- Application reads `active_version_arn` from DynamoDB at query time
- Version updates require a human to update DynamoDB (simulating an approval gate)

In production this would be backed by a ticketing or approval system. SageMaker Model
Registry has native approval workflows for model versions — Bedrock Prompt Management
does not yet have an equivalent feature.

### Bedrock Prompt Flows
Flows is a visual no-code orchestration tool for building GenAI pipelines by wiring
together nodes: FM invocations, prompt templates, Knowledge Bases, Lambda functions,
and conditions.

**When to use Flows vs. Step Functions:**
- Flows: simple GenAI-specific pipelines, non-engineers authoring/maintaining, no complex
  error handling needed
- Step Functions: complex orchestration, custom retry logic, non-Bedrock AWS service
  integrations, engineers owning the pipeline

The exam tests recognizing which tool fits a described scenario — not deep implementation
knowledge of either.

### Bedrock Model Invocation Logging
CloudTrail captures Bedrock control plane API calls (CreatePrompt, InvokeModel metadata)
by default. It does NOT capture prompt content or model responses.

For compliance and debugging you need Model Invocation Logging enabled separately —
this is an account-level Bedrock setting that writes full request/response payloads to:

- **S3**: long-term retention, cost-effective, queryable via Athena (used in Scenario 6)
- **CloudWatch Logs**: real-time debugging, queryable via Logs Insights

Enable both. This setting is configured in Scenario 4 Terraform and carries forward
into all subsequent scenarios.

**What invocation logs capture:** prompt content, model response, token counts, latency,
model ID, prompt template ARN and version if used.

**What they don't capture:** Guardrails internal scoring (added in Scenario 5).

## What the Exam Expects You to Know

- Prompt Management provides versioning and parameterization — not approval workflows
- Approval/promotion governance must be built on top (DynamoDB, Lambda, ticketing system)
- Prompt version ARNs are the reference mechanism — not version numbers alone
- Flows vs. Step Functions tradeoff: simplicity/no-code vs. complexity/control
- Flows node types: FM invocation, prompt, Knowledge Base, Lambda, condition
- CloudTrail covers Bedrock control plane only — not prompt content or model responses
- Model Invocation Logging must be explicitly enabled for data plane audit trail
- S3 for long-term retention/Athena querying; CloudWatch Logs for real-time debugging
- Invocation logs capture prompts and responses; they do not capture Guardrails scoring

## What to Observe

- Invoke the prompt template via API and confirm the parameterized template renders
  correctly with your `{{question}}` variable substituted
- Update DynamoDB active_version_arn and confirm the script picks up the new version
  on the next invocation without a code change
- Run a query through the hybrid search script then check CloudWatch Logs for the
  invocation log entry — verify prompt content, model ID, and token counts are present
- Check S3 for the same invocation log in JSON format under your configured prefix
- In the Flows console, test with a normal input and a nonsense input and observe
  how the condition node routes to different outputs
