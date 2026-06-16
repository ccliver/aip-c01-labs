# Scenario 07 — Cost Optimization

## Goal

Monitor Amazon Bedrock usage costs, set spend guardrails, and apply token-level
optimisation techniques to reduce the cost of generative AI workloads.

## Infrastructure deployed

| Resource | Purpose |
|---|---|
| CloudWatch Dashboard | Real-time token usage, invocation count, and latency broken out by model |
| CloudWatch Alarm | Fires when daily token spend exceeds a configurable threshold |
| AWS Budget | Monthly hard cap on Bedrock spend with SNS email alert |
| SNS topic | Delivers alarm and budget breach notifications |
| Lambda (batch demo) | Demonstrates Batch Inference job submission vs. synchronous on-demand calls |

## Key concepts

- **Input vs. output tokens** — output tokens cost more than input tokens; minimise verbose system prompts and use concise instructions.
- **Model selection** — Haiku < Sonnet < Opus in cost and capability; match model tier to task complexity.
- **Prompt caching** — Anthropic's cache-control headers reduce cost on repeated prompt prefixes; cache hit metrics appear in CloudWatch.
- **Batch inference** — asynchronous `CreateModelInvocationJob` is discounted up to 50% vs. on-demand; suited to offline workloads.
- **Cost allocation tags** — tag every Bedrock-adjacent resource so Cost Explorer shows per-scenario spend.

## What to observe

1. Run the same prompt against Haiku and a Sonnet-class model; compare token counts and compute the per-call cost difference.
2. Trigger the CloudWatch alarm by exceeding the daily token threshold and verify the SNS notification arrives.
3. Submit a Batch Inference job and compare the per-token invoice line against the synchronous on-demand rate.
4. Enable Anthropic prompt caching, invoke the same prompt 10 times, and watch cache-hit metrics appear in CloudWatch.
