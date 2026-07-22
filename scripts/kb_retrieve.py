#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = ["boto3", "typer"]
# ///
from typing import List, Optional
import os

import boto3
import typer

TOP_K = 5


def retrieve(agent_rt, kb_id: str, question: str) -> list:
    resp = agent_rt.retrieve(
        knowledgeBaseId=kb_id,
        retrievalQuery={"text": question},
        retrievalConfiguration={"vectorSearchConfiguration": {"numberOfResults": TOP_K}},
    )
    return resp.get("retrievalResults", [])


def get_guardrail_config(ssm, id_param: str, version_param: str) -> Optional[dict]:
    try:
        guardrail_id = ssm.get_parameter(Name=id_param)["Parameter"]["Value"]
        guardrail_version = ssm.get_parameter(Name=version_param)["Parameter"]["Value"]
    except ssm.exceptions.ParameterNotFound:
        return None
    return {"guardrailIdentifier": guardrail_id, "guardrailVersion": guardrail_version, "trace": "enabled"}


def generate_answer(bedrock, model_id: str, question: str, chunks: list, guardrail_config: Optional[dict] = None) -> tuple[str, bool]:
    grounding_source = "\n\n".join(c["content"]["text"] for c in chunks)
    kwargs = {
        "modelId": model_id,
        "system": [
            {"text": "Answer the question using only the information in the provided context. If the context doesn't contain the answer, say so."}
        ],
        "messages": [
            {
                "role": "user",
                "content": [
                    {"guardContent": {"text": {"text": grounding_source, "qualifiers": ["grounding_source"]}}},
                    {"guardContent": {"text": {"text": question, "qualifiers": ["query"]}}},
                ],
            }
        ],
    }
    if guardrail_config:
        kwargs["guardrailConfig"] = guardrail_config
    resp = bedrock.converse(**kwargs)
    intervened = resp["stopReason"] == "guardrail_intervened"
    text = resp["output"]["message"]["content"][0]["text"]
    return text, intervened


def print_results(question: str, chunks: list, answer: str, intervened: bool) -> None:
    print(f"\nQuery: {question}\n{'─' * 60}")
    if intervened:
        print("[guardrail intervened — response was blocked or altered]")
    print(f"\n{answer}\n{'─' * 60}")
    for chunk in chunks:
        uri = chunk.get("location", {}).get("s3Location", {}).get("uri", "unknown")
        source = uri.split("/", 3)[-1] if uri.startswith("s3://") else uri
        print(f"\nsource={source}  score={chunk.get('score', 0):.4f}")
        print(chunk["content"]["text"])
        print("─" * 60)


def main(
    question: List[str] = typer.Argument(..., help="Question to ask the Knowledge Base (no quoting needed)"),
) -> None:
    """Retrieve from a Bedrock Knowledge Base and generate an answer, grounded via the Guardrail if scenario-05 is deployed."""
    question_text = " ".join(question)

    kb_id = os.environ["KB_ID"]
    region = os.environ.get("AWS_REGION", "us-east-1")
    model_id = os.environ.get("GENERATION_MODEL_ID", "us.anthropic.claude-haiku-4-5-20251001-v1:0")
    guardrail_id_param = os.environ.get("GUARDRAIL_ID_PARAM", "/aip-c01-labs/guardrails/id")
    guardrail_version_param = os.environ.get("GUARDRAIL_VERSION_PARAM", "/aip-c01-labs/guardrails/version")

    session = boto3.Session()
    agent_rt = session.client("bedrock-agent-runtime", region_name=region)
    bedrock = session.client("bedrock-runtime", region_name=region)
    ssm = session.client("ssm", region_name=region)

    chunks = retrieve(agent_rt, kb_id, question_text)
    if not chunks:
        print("No results found.")
        raise typer.Exit()

    guardrail_config = get_guardrail_config(ssm, guardrail_id_param, guardrail_version_param)
    if not guardrail_config:
        typer.echo("No guardrail found in SSM (scenario-05 must be deployed) — proceeding without one", err=True)

    answer, intervened = generate_answer(bedrock, model_id, question_text, chunks, guardrail_config)
    print_results(question_text, chunks, answer, intervened)


if __name__ == "__main__":
    typer.run(main)
