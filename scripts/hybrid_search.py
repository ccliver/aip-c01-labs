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


def get_active_prompt_arn(dynamodb, table_name: str, prompt_id: str) -> str:
    resp = dynamodb.get_item(TableName=table_name, Key={"prompt_id": {"S": prompt_id}})
    item = resp.get("Item")
    if not item:
        raise RuntimeError(f"No prompt registry row for prompt_id={prompt_id!r}")
    if item["status"]["S"] != "approved":
        raise RuntimeError(f"Prompt {prompt_id!r} is not approved (status={item['status']['S']!r})")
    return item["active_version_arn"]["S"]


def expand_query(bedrock, prompt_arn: str, q: str) -> list[str]:
    resp = bedrock.converse(
        modelId=prompt_arn,
        promptVariables={"question": {"text": q}},
    )
    raw = "[" + resp["output"]["message"]["content"][0]["text"]  # prefill trick forces JSON output
    return [q] + json.loads(raw)


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
    bm25_weight = float(os.environ.get("BM25_WEIGHT", "0.3"))
    knn_weight = float(os.environ.get("KNN_WEIGHT", "0.7"))

    if query_expansion and not ddb_table_name:
        typer.echo("DDB_TABLE_NAME env var is required for --query-expansion (scenario-04 must be deployed)", err=True)
        raise typer.Exit(1)

    session = boto3.Session()
    creds = session.get_credentials().get_frozen_credentials()
    auth = AWS4Auth(creds.access_key, creds.secret_key, region, "aoss", session_token=creds.token)
    bedrock = session.client("bedrock-runtime", region_name=region)
    bedrock_agent_rt = session.client("bedrock-agent-runtime", region_name=rerank_region)
    dynamodb = session.client("dynamodb", region_name=region)

    ensure_pipeline(endpoint, auth, bm25_weight, knn_weight)

    if query_expansion:
        print("Expanding query...", file=sys.stderr)
        prompt_arn = get_active_prompt_arn(dynamodb, ddb_table_name, prompt_id)
        queries = expand_query(bedrock, prompt_arn, question_text)
        for i, q in enumerate(queries):
            print(f"  {'original' if i == 0 else f'variant {i}'}: {q}", file=sys.stderr)

        all_hits = []
        for q in queries:
            all_hits.extend(hybrid_search(endpoint, index, auth, bedrock, embedding_model_id, q))

        candidates = dedup_by_chunk_id(all_hits)
        print(f"\nMerged {len(all_hits)} hits → {len(candidates)} unique chunks", file=sys.stderr)

        reranked = run_rerank(bedrock_agent_rt, rerank_region, rerank_model_id, candidates, question_text)
        print_results(question_text, reranked, "=== Query expansion + hybrid + rerank ===")

    elif rerank:
        hits = hybrid_search(endpoint, index, auth, bedrock, embedding_model_id, question_text)
        if not hits:
            print("No results found.")
            raise typer.Exit()
        print_results(question_text, hits, "=== Hybrid (before reranking) ===")
        reranked = run_rerank(bedrock_agent_rt, rerank_region, rerank_model_id, hits, question_text)
        print_results(question_text, reranked, "=== After reranking ===")

    else:
        hits = hybrid_search(endpoint, index, auth, bedrock, embedding_model_id, question_text)
        if not hits:
            print("No results found.")
            raise typer.Exit()
        print_results(question_text, hits)


if __name__ == "__main__":
    typer.run(main)
