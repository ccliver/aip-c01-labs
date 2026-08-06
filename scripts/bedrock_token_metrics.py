#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = ["boto3", "typer"]
# ///
"""Invoke Bedrock Converse with a small set of varied test prompts (short, medium,
and one with a longer pasted context block) and emit the resulting InputTokens /
OutputTokens as CloudWatch custom metrics under AIP-C01/Lab, dimensioned by
Scenario=07, Model, and UseCase. Standalone cost-observability probe for
scenario-07 — no Lambda involved."""
import os

import boto3
import typer

import cw_metrics

REGION = os.environ.get("AWS_REGION", "us-east-1")
DEFAULT_MODEL_ID = os.environ.get("GENERATION_MODEL_ID", "us.anthropic.claude-sonnet-4-6")
HAIKU_MODEL_ID = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
SONNET_MODEL_ID = "us.anthropic.claude-sonnet-4-6"

# Representative "pasted context block" — long enough to meaningfully separate
# its input token count from the short/medium cases without depending on any
# external file (data/ may not be populated when this runs standalone).
LONG_CONTEXT = """Amazon Bedrock is a fully managed service that offers a choice of
high-performing foundation models from leading AI companies through a single API,
along with a broad set of capabilities to build generative AI applications with
security, privacy, and responsible AI. Because Amazon Bedrock is serverless, you
don't have to manage infrastructure, and you can securely integrate and deploy
generative AI capabilities into your applications using the AWS services you are
already familiar with.

Cost optimization on Bedrock centers on a few levers: model selection (matching
model tier to task complexity — a smaller, cheaper model is often sufficient for
classification or extraction tasks, while complex reasoning may justify a larger
model), token efficiency (concise system prompts and truncating unnecessary
context reduce both input and output token costs, since output tokens are
typically billed at a higher rate than input tokens), batch inference (submitting
asynchronous jobs via CreateModelInvocationJob is discounted versus synchronous
on-demand calls, suited to offline workloads that can tolerate latency), and
prompt caching (repeated prompt prefixes can be cached to avoid re-processing the
same tokens on every call, which is especially valuable for RAG pipelines that
reuse the same system instructions or retrieved context across many queries).
Monitoring token usage per model, per use case, and over time is a prerequisite
for all of these — you can't optimize what you aren't measuring."""

TEST_PROMPTS = [
    ("short", "What is Amazon Bedrock?"),
    (
        "medium",
        "Compare Amazon Bedrock's on-demand pricing model to its batch inference "
        "pricing model, and explain when a workload should prefer one over the other.",
    ),
    (
        "long-context",
        f"{LONG_CONTEXT}\n\nBased on the passage above, summarize the four cost "
        "optimization levers it describes in one sentence each.",
    ),
]


def converse(bedrock, model_id: str, prompt: str) -> dict:
    return bedrock.converse(
        modelId=model_id,
        messages=[{"role": "user", "content": [{"text": prompt}]}],
    )


def main(
    use_case: str = typer.Option("cost-test", "--use-case", help="UseCase dimension value for the emitted metrics"),
    haiku: bool = typer.Option(False, "--haiku", help="Use Claude Haiku 4.5"),
    sonnet: bool = typer.Option(False, "--sonnet", help="Use Claude Sonnet 4.6"),
) -> None:
    """Probe Bedrock Converse token usage across short/medium/long-context prompts and emit CloudWatch metrics."""
    if haiku and sonnet:
        typer.echo("--haiku and --sonnet are mutually exclusive", err=True)
        raise typer.Exit(1)
    model_id = HAIKU_MODEL_ID if haiku else SONNET_MODEL_ID if sonnet else DEFAULT_MODEL_ID

    session = boto3.Session()
    bedrock = session.client("bedrock-runtime", region_name=REGION)

    for label, prompt in TEST_PROMPTS:
        resp = converse(bedrock, model_id, prompt)
        usage = resp["usage"]
        input_tokens = usage["inputTokens"]
        output_tokens = usage["outputTokens"]

        dims = {"Scenario": "07", "Model": model_id, "UseCase": use_case}
        cw_metrics.put_metric("InputTokens", input_tokens, dims)
        cw_metrics.put_metric("OutputTokens", output_tokens, dims)

        print(f"{label:<12}  input={input_tokens:<6} output={output_tokens:<6} total={usage['totalTokens']}")


if __name__ == "__main__":
    typer.run(main)
