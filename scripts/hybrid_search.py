#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = ["boto3", "requests", "requests-aws4auth"]
# ///
import json
import os
import sys
import boto3
import requests
from requests_aws4auth import AWS4Auth

ENDPOINT = os.environ["OS_ENDPOINT"]
INDEX = os.environ["OS_INDEX"]
REGION = os.environ.get("AWS_REGION", "us-east-1")
EMBEDDING_MODEL_ID = os.environ.get("EMBEDDING_MODEL_ID", "amazon.titan-embed-text-v2:0")
CLAUDE_MODEL_ID = os.environ.get("CLAUDE_MODEL_ID", "us.anthropic.claude-haiku-4-5-20251001-v1:0")
RERANK_MODEL_ID = os.environ.get("RERANK_MODEL_ID", "amazon.rerank-v1:0")
RERANK_REGION = os.environ.get("RERANK_REGION", "us-west-2")
BM25_WEIGHT = float(os.environ.get("BM25_WEIGHT", "0.3"))
KNN_WEIGHT = float(os.environ.get("KNN_WEIGHT", "0.7"))
TOP_K = 5
PIPELINE_ID = "hybrid-pipeline"

flags = {"--rerank", "--query-expansion"}
rerank = "--rerank" in sys.argv
query_expansion = "--query-expansion" in sys.argv
cli_args = [a for a in sys.argv[1:] if a not in flags]

if not cli_args:
    print("Usage: hybrid_search.py [--rerank] [--query-expansion] <question>")
    sys.exit(1)

question = " ".join(cli_args)

session = boto3.Session()
creds = session.get_credentials().get_frozen_credentials()
auth = AWS4Auth(creds.access_key, creds.secret_key, REGION, "aoss", session_token=creds.token)
bedrock = session.client("bedrock-runtime", region_name=REGION)
bedrock_agent_rt = session.client("bedrock-agent-runtime", region_name=RERANK_REGION)

requests.put(
    f"{ENDPOINT}/_search/pipeline/{PIPELINE_ID}",
    auth=auth,
    json={
        "description": "Hybrid BM25 + kNN with min-max normalization",
        "phase_results_processors": [
            {
                "normalization-processor": {
                    "normalization": {"technique": "min_max"},
                    "combination": {
                        "technique": "arithmetic_mean",
                        "parameters": {"weights": [BM25_WEIGHT, KNN_WEIGHT]},
                    },
                }
            }
        ],
    },
).raise_for_status()


def hybrid_search(q: str) -> list:
    embed_resp = bedrock.invoke_model(
        modelId=EMBEDDING_MODEL_ID,
        body=json.dumps({"inputText": q, "dimensions": 1024, "normalize": True}),
    )
    vector = json.loads(embed_resp["body"].read())["embedding"]
    resp = requests.get(
        f"{ENDPOINT}/{INDEX}/_search?search_pipeline={PIPELINE_ID}",
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


def run_rerank(hits: list, q: str) -> list:
    resp = bedrock_agent_rt.rerank(
        rerankingConfiguration={
            "type": "BEDROCK_RERANKING_MODEL",
            "bedrockRerankingConfiguration": {
                "numberOfResults": TOP_K,
                "modelConfiguration": {
                    "modelArn": f"arn:aws:bedrock:{RERANK_REGION}::foundation-model/{RERANK_MODEL_ID}",
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


def expand_query(q: str) -> list[str]:
    resp = bedrock.converse(
        modelId=CLAUDE_MODEL_ID,
        messages=[
            {
                "role": "user",
                "content": [{"text": (
                    f"Generate 3 rephrased variants of the following question to help retrieve "
                    f"different but relevant document chunks. Return only a JSON array of 3 strings, no markdown.\n\n"
                    f"Question: {q}"
                )}],
            },
            {"role": "assistant", "content": [{"text": "["}]},
        ],
    )
    raw = "[" + resp["output"]["message"]["content"][0]["text"]
    variants = json.loads(raw)
    return [q] + variants


def dedup_by_chunk_id(all_hits: list) -> list:
    seen: dict = {}
    for hit in all_hits:
        cid = hit["_source"]["chunk_id"]
        if cid not in seen or hit["_score"] > seen[cid]["_score"]:
            seen[cid] = hit
    return sorted(seen.values(), key=lambda h: h["_score"], reverse=True)


def print_results(results: list, label: str = None):
    header = f"\nQuery: {question}"
    if label:
        header = f"\n{label}\n{header}"
    print(f"{header}\n{'─' * 60}")
    for i, hit in enumerate(results, 1):
        src = hit["_source"]
        print(f"\n[{i}] score={hit['_score']:.4f}  source={src['source_key']}  chunk={src['chunk_id']}")
        print(src["text"])
        print("─" * 60)


if query_expansion:
    print("Expanding query...", file=sys.stderr)
    queries = expand_query(question)
    for i, q in enumerate(queries):
        print(f"  {'original' if i == 0 else f'variant {i}'}: {q}", file=sys.stderr)

    all_hits = []
    for q in queries:
        all_hits.extend(hybrid_search(q))

    candidates = dedup_by_chunk_id(all_hits)
    print(f"\nMerged {len(all_hits)} hits → {len(candidates)} unique chunks", file=sys.stderr)

    reranked = run_rerank(candidates, question)
    print_results(reranked, "=== Query expansion + hybrid + rerank ===")

elif rerank:
    hits = hybrid_search(question)
    if not hits:
        print("No results found.")
        sys.exit(0)
    print_results(hits, "=== Hybrid (before reranking) ===")
    print_results(run_rerank(hits, question), "=== After reranking ===")

else:
    hits = hybrid_search(question)
    if not hits:
        print("No results found.")
        sys.exit(0)
    print_results(hits)
