#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = ["boto3", "requests", "requests-aws4auth", "typer"]
# ///
import json
import os
import sys
from typing import List, Optional

import boto3
import requests
import typer
from requests_aws4auth import AWS4Auth

import comprehend_guard

TOP_K = 5
PIPELINE_ID = "hybrid-pipeline"


def ensure_pipeline(endpoint: str, auth: AWS4Auth, bm25_weight: float, knn_weight: float) -> None:
    requests.put(
        f"{endpoint}/_search/pipeline/{PIPELINE_ID}",
        auth=auth,
        json={
            "description": "Hybrid BM25 + kNN with min-max normalization",
            "phase_results_processors": [
                {
                    "normalization-processor": {
                        "normalization": {"technique": "min_max"},
                        "combination": {
                            "technique": "arithmetic_mean",
                            "parameters": {"weights": [bm25_weight, knn_weight]},
                        },
                    }
                }
            ],
        },
    ).raise_for_status()


def hybrid_search(endpoint: str, index: str, auth: AWS4Auth, bedrock, embedding_model_id: str, q: str) -> list:
    embed_resp = bedrock.invoke_model(
        modelId=embedding_model_id,
        body=json.dumps({"inputText": q, "dimensions": 1024, "normalize": True}),
    )
    vector = json.loads(embed_resp["body"].read())["embedding"]
    resp = requests.get(
        f"{endpoint}/{index}/_search?search_pipeline={PIPELINE_ID}",
        auth=auth,
        json={
            "size": TOP_K,
            "query": {
                "hybrid": {
                    "queries": [
                        {"match": {"text": q}},
                        {"knn": {"embedding": {"vector": vector, "k": TOP_K}}},
                    ]
                }
            },
            "_source": ["source_key", "chunk_id", "text", "domain", "timestamp"],
        },
    )
    return resp.json().get("hits", {}).get("hits", [])


def run_rerank(bedrock_agent_rt, rerank_region: str, rerank_model_id: str, hits: list, q: str) -> list:
    resp = bedrock_agent_rt.rerank(
        rerankingConfiguration={
            "type": "BEDROCK_RERANKING_MODEL",
            "bedrockRerankingConfiguration": {
                "numberOfResults": TOP_K,
                "modelConfiguration": {
                    "modelArn": f"arn:aws:bedrock:{rerank_region}::foundation-model/{rerank_model_id}",
                },
            },
        },
        sources=[
            {
                "type": "INLINE",
                "inlineDocumentSource": {"type": "TEXT", "textDocument": {"text": h["_source"]["text"]}},
            }
            for h in hits
        ],
        queries=[{"type": "TEXT", "textQuery": {"text": q}}],
    )
    return [{**hits[r["index"]], "_score": r["relevanceScore"]} for r in resp["results"]]


def get_guardrail_config(ssm) -> Optional[dict]:
    id_param = os.environ.get("GUARDRAIL_ID_PARAM", "/aip-c01-labs/guardrails/id")
    version_param = os.environ.get("GUARDRAIL_VERSION_PARAM", "/aip-c01-labs/guardrails/version")
    try:
        guardrail_id = ssm.get_parameter(Name=id_param)["Parameter"]["Value"]
        guardrail_version = ssm.get_parameter(Name=version_param)["Parameter"]["Value"]
    except ssm.exceptions.ParameterNotFound:
        return None
    return {"guardrailIdentifier": guardrail_id, "guardrailVersion": guardrail_version, "trace": "enabled"}


def get_active_prompt_arn(dynamodb, table_name: str, prompt_id: str) -> str:
    resp = dynamodb.get_item(TableName=table_name, Key={"prompt_id": {"S": prompt_id}})
    item = resp.get("Item")
    if not item:
        raise RuntimeError(f"No prompt registry row for prompt_id={prompt_id!r}")
    if item["status"]["S"] != "approved":
        raise RuntimeError(f"Prompt {prompt_id!r} is not approved (status={item['status']['S']!r})")
    return item["active_version_arn"]["S"]


def expand_query(bedrock, prompt_arn: str, q: str, guardrail_config: Optional[dict] = None) -> list[str]:
    kwargs = {"modelId": prompt_arn, "promptVariables": {"question": {"text": q}}}
    if guardrail_config:
        kwargs["guardrailConfig"] = guardrail_config
    resp = bedrock.converse(**kwargs)
    text = resp["output"]["message"]["content"][0]["text"]
    if resp["stopReason"] == "guardrail_intervened":
        raise RuntimeError(f"Guardrail blocked query expansion input: {text}")
    return [q] + json.loads("[" + text)  # prefill trick forces JSON output


def generate_answer(bedrock, model_id: str, question: str, chunks: list, guardrail_config: Optional[dict] = None) -> tuple[str, bool]:
    grounding_source = "\n\n".join(h["_source"]["text"] for h in chunks)
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


def print_answer(question: str, validation: "comprehend_guard.ResponseValidation", intervened: bool) -> None:
    print(f"\nQuery: {question}\n{'─' * 60}")
    if intervened:
        print("[guardrail intervened — response was blocked or altered]")
    if validation.low_confidence:
        print(f"[low-confidence: {'; '.join(validation.reasons)}]")
    print(f"\n{validation.response}\n{'─' * 60}")


def dedup_by_chunk_id(all_hits: list) -> list:
    seen: dict = {}
    for hit in all_hits:
        cid = hit["_source"]["chunk_id"]
        if cid not in seen or hit["_score"] > seen[cid]["_score"]:
            seen[cid] = hit
    return sorted(seen.values(), key=lambda h: h["_score"], reverse=True)


def print_results(question: str, results: list, label: Optional[str] = None) -> None:
    header = f"\nQuery: {question}"
    if label:
        header = f"\n{label}\n{header}"
    print(f"{header}\n{'─' * 60}")
    for i, hit in enumerate(results, 1):
        src = hit["_source"]
        print(f"\n[{i}] score={hit['_score']:.4f}  source={src['source_key']}  chunk={src['chunk_id']}")
        print(src["text"])
        print("─" * 60)


def main(
    question: List[str] = typer.Argument(..., help="Search question (no quoting needed)"),
    rerank: bool = typer.Option(False, "--rerank", help="Rerank hybrid search results with Bedrock"),
    query_expansion: bool = typer.Option(
        False,
        "--query-expansion",
        help="Expand the query via the managed prompt, search all variants, dedup, then rerank",
    ),
    generate: bool = typer.Option(
        False,
        "--generate",
        help="Generate a final answer from the reranked chunks, grounded via the Guardrail (requires --rerank or --query-expansion)",
    ),
) -> None:
    """Hybrid BM25 + kNN search against the scenario-01 OpenSearch index."""
    question_text = " ".join(question)

    endpoint = os.environ["OS_ENDPOINT"]
    index = os.environ["OS_INDEX"]
    region = os.environ.get("AWS_REGION", "us-east-1")
    embedding_model_id = os.environ.get("EMBEDDING_MODEL_ID", "amazon.titan-embed-text-v2:0")
    ddb_table_name = os.environ.get("DDB_TABLE_NAME")
    prompt_id = os.environ.get("PROMPT_ID", "query-expansion")
    rerank_model_id = os.environ.get("RERANK_MODEL_ID", "amazon.rerank-v1:0")
    rerank_region = os.environ.get("RERANK_REGION", "us-west-2")
    generation_model_id = os.environ.get("GENERATION_MODEL_ID", "us.anthropic.claude-haiku-4-5-20251001-v1:0")
    bm25_weight = float(os.environ.get("BM25_WEIGHT", "0.3"))
    knn_weight = float(os.environ.get("KNN_WEIGHT", "0.7"))

    if query_expansion and not ddb_table_name:
        typer.echo("DDB_TABLE_NAME env var is required for --query-expansion (scenario-04 must be deployed)", err=True)
        raise typer.Exit(1)

    if generate and not (rerank or query_expansion):
        typer.echo("--generate requires --rerank or --query-expansion", err=True)
        raise typer.Exit(1)

    session = boto3.Session()
    creds = session.get_credentials().get_frozen_credentials()
    auth = AWS4Auth(creds.access_key, creds.secret_key, region, "aoss", session_token=creds.token)
    bedrock = session.client("bedrock-runtime", region_name=region)
    bedrock_agent_rt = session.client("bedrock-agent-runtime", region_name=rerank_region)
    dynamodb = session.client("dynamodb", region_name=region)
    ssm = session.client("ssm", region_name=region)
    comprehend = session.client("comprehend", region_name=region)
    logs = session.client("logs", region_name=region)

    check = comprehend_guard.check_input(comprehend, question_text)
    for warning in check.warnings:
        print(f"[comprehend] WARNING: {warning}", file=sys.stderr)
    if check.blocked:
        typer.echo(f"Blocked: PII detected in input ({', '.join(check.pii_entity_types)})", err=True)
        raise typer.Exit(1)

    ensure_pipeline(endpoint, auth, bm25_weight, knn_weight)

    guardrail_config = None
    if query_expansion or generate:
        guardrail_config = get_guardrail_config(ssm)
        if not guardrail_config:
            print("No guardrail found in SSM (scenario-05 must be deployed) — proceeding without one", file=sys.stderr)

    if query_expansion:
        print("Expanding query...", file=sys.stderr)
        prompt_arn = get_active_prompt_arn(dynamodb, ddb_table_name, prompt_id)
        queries = expand_query(bedrock, prompt_arn, question_text, guardrail_config)
        for i, q in enumerate(queries):
            print(f"  {'original' if i == 0 else f'variant {i}'}: {q}", file=sys.stderr)

        all_hits = []
        for q in queries:
            all_hits.extend(hybrid_search(endpoint, index, auth, bedrock, embedding_model_id, q))

        candidates = dedup_by_chunk_id(all_hits)
        print(f"\nMerged {len(all_hits)} hits → {len(candidates)} unique chunks", file=sys.stderr)

        reranked = run_rerank(bedrock_agent_rt, rerank_region, rerank_model_id, candidates, question_text)
        print_results(question_text, reranked, "=== Query expansion + hybrid + rerank ===")

        if generate:
            answer, intervened = generate_answer(bedrock, generation_model_id, question_text, reranked, guardrail_config)
            validation = comprehend_guard.validate_response(logs, question_text, answer, [h["_source"]["text"] for h in reranked])
            print_answer(question_text, validation, intervened)

    elif rerank:
        hits = hybrid_search(endpoint, index, auth, bedrock, embedding_model_id, question_text)
        if not hits:
            print("No results found.")
            raise typer.Exit()
        print_results(question_text, hits, "=== Hybrid (before reranking) ===")
        reranked = run_rerank(bedrock_agent_rt, rerank_region, rerank_model_id, hits, question_text)
        print_results(question_text, reranked, "=== After reranking ===")

        if generate:
            answer, intervened = generate_answer(bedrock, generation_model_id, question_text, reranked, guardrail_config)
            validation = comprehend_guard.validate_response(logs, question_text, answer, [h["_source"]["text"] for h in reranked])
            print_answer(question_text, validation, intervened)

    else:
        hits = hybrid_search(endpoint, index, auth, bedrock, embedding_model_id, question_text)
        if not hits:
            print("No results found.")
            raise typer.Exit()
        print_results(question_text, hits)


if __name__ == "__main__":
    typer.run(main)
