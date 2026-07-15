import json
import os
import boto3
import requests
from requests_aws4auth import AWS4Auth

ENDPOINT = os.environ["OS_ENDPOINT"]
INDEX = os.environ["OS_INDEX"]
REGION = os.environ.get("AWS_REGION", "us-east-1")
EMBEDDING_MODEL_ID = os.environ.get("EMBEDDING_MODEL_ID", "amazon.titan-embed-text-v2:0")
BM25_WEIGHT = float(os.environ.get("BM25_WEIGHT", "0.3"))
KNN_WEIGHT = float(os.environ.get("KNN_WEIGHT", "0.7"))
TOP_K = int(os.environ.get("TOP_K", "5"))
PIPELINE_ID = "hybrid-pipeline"

session = boto3.Session()
bedrock = session.client("bedrock-runtime", region_name=REGION)


def _auth():
    creds = session.get_credentials().get_frozen_credentials()
    return AWS4Auth(creds.access_key, creds.secret_key, REGION, "aoss", session_token=creds.token)


def _ensure_pipeline(auth):
    requests.put(
        f"https://{ENDPOINT}/_search/pipeline/{PIPELINE_ID}",
        auth=auth,
        json={
            "description": "Hybrid BM25 + kNN",
            "phase_results_processors": [{
                "normalization-processor": {
                    "normalization": {"technique": "min_max"},
                    "combination": {
                        "technique": "arithmetic_mean",
                        "parameters": {"weights": [BM25_WEIGHT, KNN_WEIGHT]},
                    },
                }
            }],
        },
    ).raise_for_status()


def _search(auth, query: str) -> list:
    embed_resp = bedrock.invoke_model(
        modelId=EMBEDDING_MODEL_ID,
        body=json.dumps({"inputText": query, "dimensions": 1024, "normalize": True}),
    )
    vector = json.loads(embed_resp["body"].read())["embedding"]

    resp = requests.get(
        f"https://{ENDPOINT}/{INDEX}/_search?search_pipeline={PIPELINE_ID}",
        auth=auth,
        json={
            "size": TOP_K,
            "query": {"hybrid": {"queries": [
                {"match": {"text": query}},
                {"knn": {"embedding": {"vector": vector, "k": TOP_K}}},
            ]}},
            "_source": ["source_key", "chunk_id", "text"],
        },
    )
    resp.raise_for_status()
    return [
        {
            "chunk_id": h["_source"]["chunk_id"],
            "source_key": h["_source"]["source_key"],
            "text": h["_source"]["text"],
            "score": h["_score"],
        }
        for h in resp.json().get("hits", {}).get("hits", [])
    ]


def _merge(question: str, results_sets: list) -> dict:
    seen: dict = {}
    for rs in results_sets:
        for r in rs["results"]:
            cid = r["chunk_id"]
            if cid not in seen or r["score"] > seen[cid]["score"]:
                seen[cid] = r

    candidates = sorted(seen.values(), key=lambda x: x["score"], reverse=True)

    # PascalCase so the Step Functions SDK integration can pass Sources directly to Bedrock Rerank
    sources = [
        {
            "Type": "INLINE",
            "InlineDocumentSource": {
                "Type": "TEXT",
                "TextDocument": {"Text": c["text"]},
            },
        }
        for c in candidates
    ]

    return {"question": question, "candidates": candidates, "sources": sources}


def lambda_handler(event, context):
    if "query" in event:
        auth = _auth()
        _ensure_pipeline(auth)
        return {"results": _search(auth, event["query"])}

    return _merge(event["question"], event["results_sets"])
