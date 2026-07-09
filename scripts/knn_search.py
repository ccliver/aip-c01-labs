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
TOP_K = 5

if len(sys.argv) < 2:
    print("Usage: knn_search.py <question>")
    sys.exit(1)

question = " ".join(sys.argv[1:])

session = boto3.Session()
creds = session.get_credentials().get_frozen_credentials()
auth = AWS4Auth(creds.access_key, creds.secret_key, REGION, "aoss", session_token=creds.token)
bedrock = session.client("bedrock-runtime", region_name=REGION)

embed_response = bedrock.invoke_model(
    modelId=EMBEDDING_MODEL_ID,
    body=json.dumps({"inputText": question, "dimensions": 1024, "normalize": True}),
)
vector = json.loads(embed_response["body"].read())["embedding"]

search_response = requests.get(
    f"{ENDPOINT}/{INDEX}/_search",
    auth=auth,
    json={
        "size": TOP_K,
        "query": {
            "knn": {
                "embedding": {
                    "vector": vector,
                    "k": TOP_K,
                }
            }
        },
        "_source": ["source_key", "chunk_id", "text", "domain", "timestamp"],
    },
)

results = search_response.json()
hits = results.get("hits", {}).get("hits", [])

if not hits:
    print("No results found.")
    sys.exit(0)

print(f"\nQuery: {question}\n{'─' * 60}")
for i, hit in enumerate(hits, 1):
    src = hit["_source"]
    score = hit["_score"]
    print(f"\n[{i}] score={score:.4f}  source={src['source_key']}  chunk={src['chunk_id']}")
    print(src["text"])
    print("─" * 60)
